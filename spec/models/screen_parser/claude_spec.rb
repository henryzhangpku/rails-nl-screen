require "rails_helper"

RSpec.describe ScreenParser::Claude do
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
    expect { described_class.parse("anything", chat: chat) }.to raise_error(/stopped early/)
  end

  it "labels screens with the model and a fingerprint of the in-code prompt when PromptEngine has none" do
    expect(described_class.label).to match(/\Aclaude-sonnet-5-5, prompt [0-9a-f]{8}\z/)
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
      expect(described_class.label).to eq "claude-sonnet-5-5, prompt screen-parser v1"

      prompt.update!(system_message: "Edited again")
      expect(described_class.label).to eq "claude-sonnet-5-5, prompt screen-parser v2"
    end

    it "falls back to the in-code prompt when the stored one is archived" do
      prompt.update!(status: "archived")
      described_class.parse("RSI under 30", chat: chat)

      expect(chat).to have_received(:with_instructions).with(described_class::SYSTEM_PROMPT)
    end
  end
end
