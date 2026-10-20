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

  # Pretends to be ScreenParser::LLM: one good condition, one out of range, one off the
  # whitelist, one this demo can't compute, and something it says it couldn't express.
  let(:fake_llm) do
    Module.new do
      def self.label = "fake-llm"

      def self.parse(_text)
        ScreenParser::Result.new(
          conditions: [ { "field" => "rsi14", "op" => ">", "value" => 50 }, { "field" => "rsi14", "op" => ">", "value" => 500 },
                        { "field" => "horoscope", "op" => ">", "value" => 1 }, { "field" => "net_income_ttm", "op" => ">", "value" => 0 } ],
          unmapped: [ { "text" => "with good vibes", "reason" => "sentiment is not a field" } ],
          rank: [ { "field" => "rsi14", "direction" => "desc", "weight" => 1 } ],
          universe: { "sectors" => [ "Energy" ] }
        )
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
    it "builds a screen spec with the rule-based parser" do
      screen = described_class.from_query("RSI under 30, MACD crossing up", parser: ScreenParser)
      expect(screen.save).to be true
      expect(screen.source).to eq "rules"
      expect(screen.conditions.map(&:label)).to eq [ "Daily RSI (14) under 30", "Daily MACD crossed above its signal on the last session" ]
      expect(screen.spec).to include("version" => 1, "observation" => "RSI under 30, MACD crossing up", "top_n" => 5, "unmapped" => [],
                                     "rank" => [ { "field" => "rsi14", "direction" => "asc", "weight" => 1 } ])
    end

    it "lets the LLM only propose: whatever breaks the contract is not screened, with the reason" do
      screen = described_class.from_query("anything", parser: fake_llm)
      expect(screen).to have_attributes(source: "llm", parser: "fake-llm")
      expect(screen.conditions.map(&:label)).to eq [ "RSI (14-day) > 50" ]
      expect(screen.not_screened.map { _1["reason"] }).to eq [
        "sentiment is not a field",
        "conditions[1]: rsi14 thresholds must be within 0-100",
        "conditions[2]: unknown field \"horoscope\"; it is not in the whitelist of computed fields",
        "Net income, last 12 months needs financial statements (SEC filings), which this demo doesn't load",
        "the universe here is a fixed list of #{Universe.symbols.size} large US stocks; sectors, industries and market caps aren't loaded"
      ]
      expect(screen.spec["rank"]).to eq [ { "field" => "rsi14", "direction" => "desc", "weight" => 1 } ]
      expect(screen.proposal["conditions"].size).to eq 4 # the raw proposal is kept, including what was refused
    end

    {
      "the provider returns an error" => RubyLLM::RateLimitError.new("slow down"),
      "the network fails"             => Faraday::TimeoutError.new("execution expired"),
      "the reply isn't JSON"          => JSON::ParserError.new("unexpected token"),
      "the model stops early"         => ScreenParser::LLM::IncompleteResponse.new("stopped early (length)")
    }.each do |what, error|
      it "falls back to the rules when #{what}" do
        screen = described_class.from_query("RSI under 30", parser: failing_llm(error))
        expect(screen).to have_attributes(source: "rules", parser: "rules v2")
        expect(screen.conditions.map(&:label)).to eq [ "Daily RSI (14) under 30" ]
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
          ScreenParser::Result.new(conditions: (20..32).map { |value| { "field" => "rsi14", "op" => "<", "value" => value } })
        end
      end

      screen = described_class.from_query("a very long screen", parser: many)

      expect(screen.conditions.map(&:value)).to eq (20..29).to_a
      expect(screen.notes).to eq [ "Kept the first 10 conditions" ]
      expect(screen.save).to be true
    end

    it "is invalid when nothing in the query is recognised" do
      expect(described_class.from_query("good vibes only", parser: ScreenParser)).not_to be_valid
    end

    it "says why when nothing can be screened here" do
      screen = described_class.from_query("price above the 21-day EMA", parser: ScreenParser).tap(&:validate)
      expect(screen.errors.full_messages.first).to start_with "Nothing in that can be screened here: price above the 21-day ema (there is no EMA field"
    end
  end

  describe "#run" do
    subject(:screen) do
      described_class.from_query("RSI above 70, price above the 200-day moving average", parser: ScreenParser).tap(&:save!)
    end

    it "records matches with the values it used and why, and skips symbols without data" do
      screen.run(%w[UP DOWN MISSING], source: fake_source)

      expect(screen).to be_done
      expect(screen.scanned_count).to eq 3
      expect(screen.matches.map(&:symbol)).to eq [ "UP" ]
      match = screen.matches.first
      expect(match.details.keys).to include("rsi14", "close", "sma200", "pct_vs_sma200")
      expect(match.why).to eq "RSI (14-day) > 70: 100 · Price above its 200-day average: $399 vs $299.5"
      expect(screen.notes.last).to include "MISSING"
      expect(Bar.where(symbol: "UP").count).to eq 300
    end

    it "records the funnel: in, passed, failed and missing data at each step" do
      short = Module.new do
        def self.fetch(_symbol) = (0...100).map { |i| { date: Date.new(2025, 1, 1) + i, open: 1, high: 1, low: 1, close: 100.0 + i, volume: 1 } }
        def self.name = "ShortHistory"
      end
      screen.run(%w[UP DOWN], source: fake_source)
      expect(screen.funnel.map { _1.values_at("step", "n_in", "n_pass", "n_fail", "n_missing") }).to eq [
        [ "2 stocks with prices", 2, 2, 0, 0 ], [ "RSI (14-day) > 70", 2, 1, 1, 0 ], [ "Price above its 200-day average", 1, 1, 0, 0 ]
      ]

      screen.run(%w[NEW], source: short) # 100 bars: no 200-day average yet, so a gap, never a guess
      expect(screen.funnel.last.values_at("n_in", "n_missing")).to eq [ 1, 1 ]
      expect(screen.matches).to be_empty
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

    it "ranks matches by the spec's ranking, as EquityScout does" do
      screen.run(%w[UP FAST DOWN], source: fake_source)

      # Both have RSI 100 (a tie); FAST is further above its 200-day average.
      expect(screen.matches.map { [ _1.symbol, _1.rank ] }).to eq [ [ "FAST", 1 ], [ "UP", 2 ] ]
      expect(screen.matches.map(&:score)).to eq [ (0.75 + 1.0) / 2, (0.75 + 0.5) / 2 ]
    end
  end
end
