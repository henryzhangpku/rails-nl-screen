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

  # Pretends to be ScreenParser::LLM, proposing one good and two bad conditions.
  let(:fake_llm) do
    Module.new do
      def self.label = "fake-llm"

      def self.parse(_text)
        ScreenParser::Result.new([ { indicator: "rsi", operator: "above", value: 50, timeframe: "daily", period: nil },
                                   { indicator: "rsi", operator: "above", value: 500, timeframe: "daily", period: nil },
                                   { indicator: "horoscope", operator: "above", value: 1, timeframe: "daily", period: nil } ],
                                 [ "with good vibes" ])
      end
    end
  end

  # Pretends to be ScreenParser::LLM, raising what it's told to.
  def failing_llm(error)
    Module.new do
      define_singleton_method(:label) { "failing-llm" }
      define_singleton_method(:parse) { |_text| raise error }
    end
  end

  describe ".from_query" do
    it "builds validated conditions with the rule-based parser" do
      screen = described_class.from_query("RSI under 30, MACD crossing up", parser: ScreenParser)
      expect(screen.save).to be true
      expect(screen.source).to eq "rules"
      expect(screen.conditions.map(&:label)).to eq [ "RSI(14) below 30", "MACD crosses above signal" ]
    end

    it "lets the LLM only propose: invalid conditions are dropped and reported" do
      screen = described_class.from_query("anything", parser: fake_llm)
      expect(screen).to have_attributes(source: "llm", parser: "fake-llm")
      expect(screen.conditions.map(&:label)).to eq [ "RSI(14) above 50" ]
      expect(screen.notes.size).to eq 3
      expect(screen.notes.first).to match(/Dropped rsi above 500/)
      expect(screen.proposal["conditions"].size).to eq 3 # the raw proposal is kept, including what was dropped
    end

    {
      "the provider returns an error" => RubyLLM::RateLimitError.new("slow down"),
      "the network fails"             => Faraday::TimeoutError.new("execution expired"),
      "the reply isn't JSON"          => JSON::ParserError.new("unexpected token"),
      "the model stops early"         => ScreenParser::LLM::IncompleteResponse.new("stopped early (length)")
    }.each do |what, error|
      it "falls back to the rules when #{what}" do
        screen = described_class.from_query("RSI under 30", parser: failing_llm(error))
        expect(screen).to have_attributes(source: "rules", parser: "rules v1")
        expect(screen.conditions.map(&:label)).to eq [ "RSI(14) below 30" ]
        expect(screen.notes.first).to eq "The LLM was unavailable (#{error.class.name.demodulize}), so the rule-based parser was used"
      end
    end

    it "lets a bug in the parser raise instead of hiding it behind the fallback" do
      expect { described_class.from_query("RSI under 30", parser: failing_llm(NoMethodError.new("undefined method"))) }
        .to raise_error(NoMethodError)
    end

    it "keeps at most #{described_class::MAX_CONDITIONS} conditions, and says so" do
      many = Module.new do
        def self.label = "many"
        def self.parse(_text)
          ScreenParser::Result.new((20..32).map { |value| { indicator: "rsi", operator: "below", value: value } }, [])
        end
      end

      screen = described_class.from_query("a very long screen", parser: many)

      expect(screen.conditions.map(&:value)).to eq (20..29).map(&:to_f)
      expect(screen.notes).to eq [ "Kept the first 10 conditions" ]
      expect(screen.save).to be true
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

    it "starts over when run again, so no symbol matches twice" do
      2.times { screen.run(%w[UP FAST DOWN MISSING], source: fake_source) }

      expect(screen.matches.map(&:symbol)).to eq %w[FAST UP]
      expect(Match.where(screen: screen).count).to eq 2
      expect(screen.reload.matches_count).to eq 2
      expect(screen.notes.grep(/No data/)).to eq [ "No data for 1 symbol(s): MISSING" ]
    end

    it "fails when no symbol has data, so the job can retry" do
      expect { screen.run(%w[MISSING], source: fake_source) }.to raise_error(MarketData::Error, /No data for any/)
      expect(screen.reload).to be_failed
    end

    it "ranks matches by how decisively they pass" do
      screen.run(%w[UP FAST DOWN], source: fake_source)

      expect(screen.matches.map(&:symbol)).to eq %w[FAST UP] # FAST is further above its SMA200
      expect(screen.matches.map(&:score)).to all(be_between(0, 1))
    end
  end
end
