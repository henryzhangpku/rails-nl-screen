require "test_helper"

class ScreenTest < ActiveSupport::TestCase
  # Pretends to be MarketData::Yahoo: UP rises steadily, FAST rises twice as fast,
  # DOWN falls, MISSING has no data.
  module FakeSource
    def self.fetch(symbol)
      raise MarketData::Error, "no data" if symbol == "MISSING"
      step = { "UP" => 1, "FAST" => 2 }.fetch(symbol, -0.2)
      (0...300).map do |i|
        close = 100.0 + i * step
        { date: Date.new(2025, 1, 1) + i, open: close, high: close + 1, low: close - 1, close: close, volume: 1_000 }
      end
    end
  end

  # Pretends to be ScreenParser::Claude.
  module FakeClaude
    def self.label = "fake-claude"

    def self.parse(_text)
      ScreenParser::Result.new([ { indicator: "rsi", operator: "above", value: 50, timeframe: "daily", period: nil },
                                 { indicator: "rsi", operator: "above", value: 500, timeframe: "daily", period: nil },
                                 { indicator: "horoscope", operator: "above", value: 1, timeframe: "daily", period: nil } ],
                               [ "with good vibes" ])
    end
  end

  module BrokenClaude
    def self.parse(_text) = raise(Timeout::Error)
  end

  test "builds validated conditions from the rule-based parser" do
    screen = Screen.from_query("RSI under 30, MACD crossing up", parser: ScreenParser)
    assert screen.save
    assert_equal "rules", screen.source
    assert_equal [ "RSI(14) below 30", "MACD crosses above signal" ], screen.conditions.map(&:label)
  end

  test "Claude only proposes: invalid conditions are dropped and reported" do
    screen = Screen.from_query("anything", parser: FakeClaude)
    assert_equal "claude", screen.source
    assert_equal [ "RSI(14) above 50" ], screen.conditions.map(&:label)
    assert_equal 3, screen.notes.size
    assert_match(/Dropped rsi above 500/, screen.notes.first)
    assert_equal "fake-claude", screen.parser
    assert_equal 3, screen.proposal["conditions"].size # the raw proposal is kept, including what was dropped
  end

  test "falls back to the rules when Claude fails" do
    screen = Screen.from_query("RSI under 30", parser: BrokenClaude)
    assert_equal "rules", screen.source
    assert_equal [ "RSI(14) below 30" ], screen.conditions.map(&:label)
    assert_match(/rule-based parser was used/, screen.notes.first)
    assert_equal "rules v1", screen.parser
  end

  test "matches are ranked by how decisively they pass" do
    screen = Screen.from_query("RSI above 70, price above the 200-day moving average", parser: ScreenParser)
    screen.save!
    screen.run(%w[UP FAST DOWN], source: FakeSource)

    assert_equal %w[FAST UP], screen.matches.map(&:symbol) # FAST is further above its SMA200
    assert screen.matches.all? { |m| m.score.between?(0, 1) }
  end

  test "a query with no recognizable condition is invalid" do
    refute Screen.from_query("good vibes only", parser: ScreenParser).valid?
  end

  test "run records matches with values and a reason, and skips symbols without data" do
    screen = Screen.from_query("RSI above 70, price above the 200-day moving average", parser: ScreenParser)
    screen.save!

    screen.run(%w[UP DOWN MISSING], source: FakeSource)

    assert screen.done?
    assert_equal 3, screen.scanned_count
    assert_equal [ "UP" ], screen.matches.map(&:symbol)
    match = screen.matches.first
    assert_equal [ "RSI(14) above 70", "Price above SMA(200)" ], match.details.map { |d| d["label"] }
    assert_match(/RSI\(14\) 100 > 70 · close \d+(\.\d)?% above SMA200/, match.why)
    assert_includes screen.notes.last, "MISSING"
    assert_equal 300, Bar.where(symbol: "UP").count
  end
end
