require "rails_helper"

# Goes through RubyLLM's real HTTP client against a stubbed DeepSeek endpoint, to check
# the provider routing, the JSON-object fallback (DeepSeek's chat API has no strict
# schemas) and the parsing, end to end, without a key or a network call.
RSpec.describe ScreenParser::LLM, "with DeepSeek" do
  let(:reply_json) do
    { conditions: [ { indicator: "rsi", timeframe: "daily", operator: "below", period: 14, value: 30 } ],
      unrecognized: [ "good vibes" ] }.to_json
  end

  around do |example|
    saved = RubyLLM.config.deepseek_api_key
    RubyLLM.config.deepseek_api_key = "sk-test"
    ENV["SCREEN_PARSER_MODEL"] = "deepseek-v4-flash"
    example.run
  ensure
    RubyLLM.config.deepseek_api_key = saved
    ENV.delete("SCREEN_PARSER_MODEL")
  end

  before do
    stub_request(:post, "https://api.deepseek.com/chat/completions").to_return(
      headers: { "Content-Type" => "application/json" },
      body: { id: "1", object: "chat.completion", model: "deepseek-v4-flash",
              choices: [ { index: 0, finish_reason: "stop", message: { role: "assistant", content: reply_json } } ],
              usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 } }.to_json
    )
  end

  it "asks DeepSeek for a JSON object with the instructions and query, and parses the proposal" do
    screen = Screen.from_query("RSI under 30, good vibes")

    expect(screen).to have_attributes(source: "llm", parser: start_with("deepseek-v4-flash, prompt "))
    expect(screen.conditions.map(&:label)).to eq [ "RSI(14) below 30" ]
    expect(screen.notes.join).to include("good vibes")

    expect(WebMock).to(have_requested(:post, "https://api.deepseek.com/chat/completions").with do |request|
      body = JSON.parse(request.body)
      body["model"] == "deepseek-v4-flash" &&
        body["response_format"] == { "type" => "json_object" } &&
        body["messages"].first["content"].include?("Reply with only a JSON object") &&
        body["messages"].last["content"] == "RSI under 30, good vibes" &&
        request.headers["Authorization"] == "Bearer sk-test"
    end)
  end
end
