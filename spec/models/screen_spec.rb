require "rails_helper"

RSpec.describe Screen do
  # Pretends to be MarketData::Yahoo: UP rises steadily, FAST rises twice as fast,
  # DOWN falls, MISSING has no data.
  let(:fake_source) do
    Module.new do
      def self.fetch(symbol)
        raise MarketData::Error, "no data" if symbol == "MISSING"
        step = { "UP" => 1, "FAST" => 2 }.fetch(symbol, -0.2)
        (0...300).map do |i|
          close = 100.0 + i * step
          { date: Date.new(2025, 1, 1) + i, open: close, high: close + 1, low: close - 1, close: close, volume: 1_000 }
        end
      end

      def self.name = "FakeSource"
    end
  end

  # Pretends to be ScreenParser::Claude, proposing one good and two bad conditions.
  let(:fake_claude) do
    Module.new do
      def self.label = "fake-claude"

      def self.parse(_text)
        ScreenParser::Result.new([ { indicator: "rsi", operator: "above", value: 50, timeframe: "daily", period: nil },
                                   { indicator: "rsi", operator: "above", value: 500, timeframe: "daily", period: nil },
                                   { indicator: "horoscope", operator: "above", value: 1, timeframe: "daily", period: nil } ],
                                 [ "with good vibes" ])
      end
    end
  end

  let(:broken_claude) { Module.new { def self.parse(_text) = raise(Timeout::Error) } }

  describe ".from_query" do
    it "builds validated conditions with the rule-based parser" do
      screen = described_class.from_query("RSI under 30, MACD crossing up", parser: ScreenParser)
      expect(screen.save).to be true
      expect(screen.source).to eq "rules"
      expect(screen.conditions.map(&:label)).to eq [ "RSI(14) below 30", "MACD crosses above signal" ]
    end

    it "lets Claude only propose: invalid conditions are dropped and reported" do
      screen = described_class.from_query("anything", parser: fake_claude)
      expect(screen).to have_attributes(source: "llm", parser: "fake-claude")
      expect(screen.conditions.map(&:label)).to eq [ "RSI(14) above 50" ]
      expect(screen.notes.size).to eq 3
      expect(screen.notes.first).to match(/Dropped rsi above 500/)
      expect(screen.proposal["conditions"].size).to eq 3 # the raw proposal is kept, including what was dropped
    end

    it "falls back to the rules when Claude fails" do
      screen = described_class.from_query("RSI under 30", parser: broken_claude)
      expect(screen).to have_attributes(source: "rules", parser: "rules v1")
      expect(screen.conditions.map(&:label)).to eq [ "RSI(14) below 30" ]
      expect(screen.notes.first).to match(/rule-based parser was used/)
    end

    it "is invalid when nothing in the query is recognised" do
      expect(described_class.from_query("good vibes only", parser: ScreenParser)).not_to be_valid
    end
  end

  describe "#run" do
    subject(:screen) do
      described_class.from_query("RSI above 70, price above the 200-day moving average", parser: ScreenParser).tap(&:save!)
    end

    it "records matches with observed values and a reason, and skips symbols without data" do
      screen.run(%w[UP DOWN MISSING], source: fake_source)

      expect(screen).to be_done
      expect(screen.scanned_count).to eq 3
      expect(screen.matches.map(&:symbol)).to eq [ "UP" ]
      match = screen.matches.first
      expect(match.details.map { |d| d["label"] }).to eq [ "RSI(14) above 70", "Price above SMA(200)" ]
      expect(match.why).to match(/RSI\(14\) 100 > 70 · close \d+(\.\d)?% above SMA200/)
      expect(screen.notes.last).to include "MISSING"
      expect(Bar.where(symbol: "UP").count).to eq 300
    end

    it "keeps the matches_count counter cache in step with the matches" do
      screen.run(%w[UP FAST DOWN], source: fake_source)
      expect(screen.matches_count).to eq 2
      expect(screen.reload.matches_count).to eq 2
    end

    it "ranks matches by how decisively they pass" do
      screen.run(%w[UP FAST DOWN], source: fake_source)

      expect(screen.matches.map(&:symbol)).to eq %w[FAST UP] # FAST is further above its SMA200
      expect(screen.matches.map(&:score)).to all(be_between(0, 1))
    end
  end
end
