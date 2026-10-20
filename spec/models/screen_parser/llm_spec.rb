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
    { "conditions" => [ { "field" => "rsi14", "op" => "<", "value" => 30, "ref" => nil, "why" => "oversold" } ],
      "rank" => [ { "field" => "rsi14", "direction" => "asc", "weight" => 1 } ],
      "universe" => { "min_price" => 5, "sectors" => nil }, "top_n" => 3,
      "unmapped" => [ { "text" => "good vibes", "reason" => "sentiment is not a field" } ], "notes" => "" }
  end

  it "asks for structured output constrained to the whitelist schema" do
    described_class.parse("RSI under 30, good vibes", chat: chat)

    expect(chat).to have_received(:with_instructions).with(described_class::SYSTEM_PROMPT)
    expect(chat).to have_received(:with_schema).with(described_class::SCHEMA)
    expect(chat).to have_received(:ask).with("RSI under 30, good vibes")
    expect(described_class::SCHEMA.dig(:properties, :conditions, :items, :properties, :field, :enum)).to eq ScreenSpec::FIELDS.keys
    expect(described_class::SCHEMA.dig(:properties, :conditions, :items, :properties, :op, :enum)).to eq ScreenSpec::OPS
  end

  it "returns the proposal as a parser result, nulls meaning 'not used'" do
    result = described_class.parse("RSI under 30, good vibes", chat: chat)
    expect(result.conditions).to eq [ { "field" => "rsi14", "op" => "<", "value" => 30, "why" => "oversold" } ]
    expect(result.unmapped).to eq [ { "text" => "good vibes", "reason" => "sentiment is not a field" } ]
    expect(result).to have_attributes(rank: [ { "field" => "rsi14", "direction" => "asc", "weight" => 1 } ],
                                      universe: { "min_price" => 5 }, top_n: 3)
  end

  it "describes the contract's fields and rules to the model" do
    expect(described_class::SYSTEM_PROMPT).to include("drawdown_52w | ratio |", "macd_cross_up_w | bool |", "Ratios are decimals: 0.10 means 10%")
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

  it "reads loosely shaped JSON defensively, leaving the rest to the contract" do
    loose = Struct.new(:finish_reason, :parsed).new(:stop, { "conditions" => [ { "field" => "rsi14" }, "junk" ] })
    allow(chat).to receive(:ask).and_return(loose)

    result = described_class.parse("RSI", chat: chat)
    expect(result.conditions).to eq [ { "field" => "rsi14" }, "junk" ]
    expect(result).to have_attributes(unmapped: [], rank: [], universe: {}, top_n: nil)
  end

  # A model can still reply outside the schema (not every provider enforces it).
  # Whatever it sends, the screen ends with that part not screened (with the reason),
  # or parsed by the rules instead; never with an exception.
  describe "odd replies, through Screen.from_query" do
    let(:good) { { "field" => "rsi14", "op" => "<", "value" => 30 } }
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
      "an object value"     => [ { "value" => {} }, /value must be a number/ ],
      "a string value"      => [ { "value" => "30" }, /value must be a number/ ],
      "a numeric field"     => [ { "field" => 5 }, /unknown field 5/ ],
      "a value and a ref"   => [ { "ref" => "rsi14_w" }, /give exactly one of 'value'/ ],
      "a percent, not a ratio" => [ { "field" => "drawdown_52w", "op" => "<=", "value" => -25 }, /looks like a percent/ ]
    }.each do |what, (override, reason)|
      it "refuses a condition with #{what} and says why" do
        screen = screen_for("conditions" => [ good.merge(override), good ])

        expect(screen.source).to eq "llm"
        expect(screen.conditions.map(&:label)).to eq [ "Daily RSI (14) under 30" ]
        expect(screen.not_screened.map { _1["reason"] }).to contain_exactly(reason)
      end
    end

    it "refuses a condition that isn't an object" do
      screen = screen_for("conditions" => [ "rsi < 30", good ])
      expect(screen.not_screened.first["reason"]).to eq "conditions[0] must be an object"
    end

    it "falls back to the rules when conditions is not an array" do
      screen = screen_for("conditions" => "x")

      expect(screen).to have_attributes(source: "rules", parser: "rules v2")
      expect(screen.conditions.map(&:label)).to eq [ "Daily RSI (14) under 30" ]
      expect(screen.notes).to contain_exactly(/MalformedResponse/)
    end

    it "falls back to the rules when the reply is not JSON at all" do
      expect(screen_for("I can't help with that").source).to eq "rules"
    end
  end
end
