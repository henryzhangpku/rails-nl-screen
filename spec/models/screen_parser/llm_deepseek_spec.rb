require "rails_helper"

# Goes through RubyLLM's real HTTP client against stubbed DeepSeek endpoints, to check
# the provider routing, the protocol choice and the parsing end to end, without a key
# or a network call.
RSpec.describe ScreenParser::LLM, "with DeepSeek" do
  let(:proposal) do
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
    ENV.delete("SCREEN_PARSER_PROTOCOL")
  end

  def expect_parsed(screen)
    expect(screen).to have_attributes(source: "llm", parser: start_with("deepseek-v4-flash, prompt "))
    expect(screen.conditions.map(&:label)).to eq [ "RSI(14) below 30" ]
    expect(screen.notes.join).to include("good vibes")
  end

  it "uses DeepSeek's Responses API, which takes the JSON schema" do
    stub_request(:post, "https://api.deepseek.com/responses").to_return(
      headers: { "Content-Type" => "application/json" },
      body: { id: "resp_1", object: "response", model: "deepseek-v4-flash", status: "completed",
              output: [ { type: "message", role: "assistant", content: [ { type: "output_text", text: proposal } ] } ],
              usage: { input_tokens: 10, output_tokens: 20 } }.to_json
    )

    expect_parsed(Screen.from_query("RSI under 30, good vibes"))

    expect(WebMock).to(have_requested(:post, "https://api.deepseek.com/responses").with do |request|
      body = JSON.parse(request.body)
      format = body.dig("text", "format")
      body["model"] == "deepseek-v4-flash" &&
        format["type"] == "json_schema" &&
        format.dig("schema", "properties", "conditions", "items", "properties", "indicator", "enum") == Condition::SPECS.keys &&
        request.body.include?("RSI under 30, good vibes") &&
        request.headers["Authorization"] == "Bearer sk-test"
    end)
  end

  it "can use chat completions instead, which only promise a JSON object" do
    ENV["SCREEN_PARSER_PROTOCOL"] = "chat_completions"
    stub_request(:post, "https://api.deepseek.com/chat/completions").to_return(
      headers: { "Content-Type" => "application/json" },
      body: { id: "1", object: "chat.completion", model: "deepseek-v4-flash",
              choices: [ { index: 0, finish_reason: "stop", message: { role: "assistant", content: proposal } } ],
              usage: { prompt_tokens: 10, completion_tokens: 20, total_tokens: 30 } }.to_json
    )

    expect_parsed(Screen.from_query("RSI under 30, good vibes"))

    expect(WebMock).to(have_requested(:post, "https://api.deepseek.com/chat/completions").with do |request|
      body = JSON.parse(request.body)
      body["response_format"] == { "type" => "json_object" } &&
        body["messages"].first["content"].include?("Reply with only a JSON object")
    end)
  end
end
