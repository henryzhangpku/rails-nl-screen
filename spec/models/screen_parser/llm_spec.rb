require "rails_helper"

RSpec.describe ScreenParser::LLM do
  # Stands in for a RubyLLM::Chat: records what it was given, returns a canned reply.
  let(:reply) { Struct.new(:finish_reason, :parsed).new(:stop, proposal) }
  let(:chat) do
    instance_double(RubyLLM::Chat).tap do |chat|
      allow(chat).to receive(:with_instructions).and_return(chat)
      allow(chat).to receive(:with_schema).and_return(chat)
      allow(chat).to receive(:ask).and_return(reply)
    end
  end
  let(:proposal) do
    { "conditions" => [ { "indicator" => "rsi", "timeframe" => "daily", "operator" => "below", "period" => 14, "value" => 30 } ],
      "unrecognized" => [ "good vibes" ] }
  end

  it "asks for structured output constrained to the whitelist schema" do
    described_class.parse("RSI under 30, good vibes", chat: chat)

    expect(chat).to have_received(:with_instructions).with(described_class::SYSTEM_PROMPT)
    expect(chat).to have_received(:with_schema).with(described_class::SCHEMA)
    expect(chat).to have_received(:ask).with("RSI under 30, good vibes")
    expect(described_class::SCHEMA.dig(:properties, :conditions, :items, :properties, :indicator, :enum))
      .to eq Condition::SPECS.keys
  end

  it "returns the proposal as a parser result" do
    result = described_class.parse("RSI under 30, good vibes", chat: chat)
    expect(result.conditions).to eq [ { indicator: "rsi", timeframe: "daily", operator: "below", period: 14, value: 30 } ]
    expect(result.unrecognized).to eq [ "good vibes" ]
  end

  it "raises when the model stops early, so the caller falls back to the rules" do
    allow(chat).to receive(:ask).and_return(Struct.new(:finish_reason, :parsed).new(:content_filter, nil))
    expect { described_class.parse("anything", chat: chat) }.to raise_error(described_class::IncompleteResponse, /stopped early \(content_filter\)/)
  end

  it "labels screens with the model and a fingerprint of the in-code prompt when PromptEngine has none" do
    expect(described_class.label).to match(/\Adeepseek-v4-flash, prompt [0-9a-f]{8}\z/)
  end

  context "with the prompt stored in PromptEngine" do
    let!(:prompt) do
      PromptEngine::Prompt.create!(name: described_class::PROMPT_NAME, status: "active", model: described_class::MODEL,
                                   system_message: "Edited instructions", content: "Screen: {{query}}")
    end

    it "sends the stored instructions and renders the query into the stored message" do
      described_class.parse("RSI under 30", chat: chat)

      expect(chat).to have_received(:with_instructions).with("Edited instructions")
      expect(chat).to have_received(:ask).with("Screen: RSI under 30")
    end

    it "labels screens with the prompt version, which goes up with every edit" do
      expect(described_class.label).to eq "deepseek-v4-flash, prompt screen-parser v1"

      prompt.update!(system_message: "Edited again")
      expect(described_class.label).to eq "deepseek-v4-flash, prompt screen-parser v2"
    end

    it "falls back to the in-code prompt when the stored one is archived" do
      prompt.update!(status: "archived")
      described_class.parse("RSI under 30", chat: chat)

      expect(chat).to have_received(:with_instructions).with(described_class::SYSTEM_PROMPT)
    end
  end

  describe "choosing the provider" do
    around do |example|
      saved = RubyLLM.config.deepseek_api_key
      example.run
    ensure
      RubyLLM.config.deepseek_api_key = saved
    end

    def with_env(vars)
      vars.each { |key, value| ENV[key] = value }
      yield
    ensure
      vars.each_key { |key| ENV.delete(key) }
    end

    it "follows the model's provider in RubyLLM's registry" do
      expect(described_class.provider_for("gpt-5")).to eq "openai"
      expect(described_class.provider_for("deepseek-v4-flash")).to eq "deepseek"
      expect(described_class.provider_for("not-a-model")).to be_nil
    end

    it "uses the provider named in the prompt's metadata for models the registry doesn't list" do
      PromptEngine::Prompt.create!(name: described_class::PROMPT_NAME, status: "active", model: "deepseek-chat",
                                   metadata: { "provider" => "deepseek" }, system_message: "x", content: "{{query}}")

      expect(described_class.request_for("q")).to have_attributes(model: "deepseek-chat", provider: "deepseek")
    end

    it "is enabled only when the chosen model's provider has a key" do
      with_env("SCREEN_PARSER_MODEL" => "deepseek-v4-flash") do
        RubyLLM.config.deepseek_api_key = nil
        expect(described_class).not_to be_enabled

        RubyLLM.config.deepseek_api_key = "sk-test"
        expect(described_class).to be_enabled
        expect(described_class.label).to start_with "deepseek-v4-flash, prompt "
      end
    end

    it "builds the chat for that model and provider" do
      allow(RubyLLM).to receive(:chat).and_return(chat)
      with_env("SCREEN_PARSER_MODEL" => "deepseek-v4-flash") { described_class.parse("RSI under 30") }

      expect(RubyLLM).to have_received(:chat)
        .with(model: "deepseek-v4-flash", provider: :deepseek, protocol: :responses, assume_model_exists: true)
    end
  end

  it "reads loosely shaped JSON defensively, leaving the rest to the Condition validations" do
    loose = Struct.new(:finish_reason, :parsed).new(:stop, { "conditions" => [ { "indicator" => "rsi" }, "junk" ] })
    allow(chat).to receive(:ask).and_return(loose)

    result = described_class.parse("RSI", chat: chat)
    expect(result.conditions).to eq [ { indicator: "rsi" } ]
    expect(result.unrecognized).to eq []
  end

  # A model can still reply outside the schema (not every provider enforces it).
  # Whatever it sends, the screen ends with that condition dropped and noted, or
  # parsed by the rules instead; never with an exception.
  describe "odd replies, through Screen.from_query" do
    let(:good) { { "indicator" => "rsi", "timeframe" => "daily", "operator" => "below", "period" => 14, "value" => 30 } }
    let(:parser) do
      llm, chat = described_class, self.chat
      Module.new do
        define_singleton_method(:label) { "test-llm" }
        define_singleton_method(:parse) { |text| llm.parse(text, chat: chat) }
      end
    end

    def screen_for(parsed)
      allow(chat).to receive(:ask).and_return(Struct.new(:finish_reason, :parsed).new(:stop, parsed))
      Screen.from_query("RSI under 30", parser: parser)
    end

    {
      "an array value"   => { "value" => [ 30 ] },
      "an object period" => { "period" => {} }
    }.each do |what, override|
      it "drops a condition with #{what} and says why" do
        screen = screen_for("conditions" => [ good.merge(override), good ], "unrecognized" => [])

        expect(screen.source).to eq "llm"
        expect(screen.conditions.map(&:label)).to eq [ "RSI(14) below 30" ]
        expect(screen.notes).to contain_exactly(/\ADropped .*: #{override.keys.first} must be a number or text\z/)
      end
    end

    it "drops a numeric indicator through the Condition validations" do
      screen = screen_for("conditions" => [ good.merge("indicator" => 5) ], "unrecognized" => [])

      expect(screen.conditions).to be_empty
      expect(screen.notes).to contain_exactly(/\ADropped 5 .*Indicator is not included in the list/)
      expect(screen).not_to be_valid
    end

    it "falls back to the rules when conditions is not an array" do
      screen = screen_for("conditions" => "x", "unrecognized" => [])

      expect(screen).to have_attributes(source: "rules", parser: "rules v1")
      expect(screen.conditions.map(&:label)).to eq [ "RSI(14) below 30" ]
      expect(screen.notes).to contain_exactly(/MalformedResponse/)
    end

    it "falls back to the rules when the reply is not JSON at all" do
      expect(screen_for("I can't help with that").source).to eq "rules"
    end
  end
end
