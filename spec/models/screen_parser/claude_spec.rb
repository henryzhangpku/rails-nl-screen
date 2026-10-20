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

  it "labels screens with the model and a fingerprint of the prompt" do
    expect(described_class.label).to match(/\Aclaude-sonnet-5-5, prompt [0-9a-f]{8}\z/)
  end
end
