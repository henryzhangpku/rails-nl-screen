require "test_helper"

class ScreenParserTest < ActiveSupport::TestCase
  def parse(text) = ScreenParser.parse(text)

  test "the representative query becomes four conditions" do
    result = parse("RSI(14) under 30 on the daily, MACD crossing up, volume above its 20-day average, price above the 200-day moving average")

    assert_equal [
      { indicator: "rsi", period: 14, operator: "below", value: 30.0, timeframe: "daily" },
      { indicator: "macd", operator: "crosses_up", timeframe: "daily" },
      { indicator: "volume", period: 20, operator: "above", value: nil, timeframe: "daily" },
      { indicator: "sma", period: 200, operator: "above", timeframe: "daily" }
    ], result.conditions
    assert_empty result.unrecognized
  end

  test "rsi variants" do
    assert_equal({ indicator: "rsi", period: nil, operator: "above", value: 70.0, timeframe: "daily" }, parse("rsi > 70").conditions.first)
    assert_equal 7, parse("RSI 7 below 25").conditions.first[:period]
    assert_equal({ indicator: "rsi", period: nil, operator: "below", value: 30.0, timeframe: "daily" }, parse("oversold").conditions.first)
    assert_equal "above", parse("overbought names").conditions.first[:operator]
  end

  test "macd direction" do
    assert_equal "crosses_down", parse("MACD bearish cross").conditions.first[:operator]
    assert_equal "crosses_up", parse("macd crosses above signal").conditions.first[:operator]
  end

  test "volume multiplier and period" do
    assert_equal({ indicator: "volume", period: 50, operator: "above", value: 2.0, timeframe: "daily" },
                 parse("volume 2x its 50-day average").conditions.first)
    assert_equal "below", parse("volume below the 10-day average").conditions.first[:operator]
  end

  test "moving averages" do
    assert_equal({ indicator: "ema", period: 21, operator: "below", timeframe: "daily" }, parse("price below the 21 day EMA").conditions.first)
    assert_equal({ indicator: "sma", period: 50, operator: "above", timeframe: "daily" }, parse("above SMA(50)").conditions.first)
  end

  test "drawdown from the 52-week high" do
    assert_equal({ indicator: "drawdown", operator: "below", value: 5.0, timeframe: "daily" }, parse("within 5% of the 52-week high").conditions.first)
    assert_equal({ indicator: "drawdown", operator: "above", value: 25.0, timeframe: "daily" }, parse("down at least 25% from its 52 week high").conditions.first)
    assert_equal 5.0, parse("near the 52-week high").conditions.first[:value]
  end

  test "price range survives the 'and' splitter" do
    assert_equal [
      { indicator: "price", operator: "above", value: 20.0, timeframe: "daily" },
      { indicator: "price", operator: "below", value: 100.0, timeframe: "daily" }
    ], parse("price between $20 and $100").conditions
    assert_equal({ indicator: "price", operator: "below", value: 50.0, timeframe: "daily" }, parse("trading under $50").conditions.first)
  end

  test "weekly timeframe is per clause" do
    conditions = parse("weekly RSI above 60, price above the 30-week moving average").conditions
    assert_equal %w[weekly daily], conditions.map { |c| c[:timeframe] }
  end

  test "unknown clauses are reported, filler is ignored" do
    result = parse("show me stocks with RSI under 30 and a nice logo")
    assert_equal 1, result.conditions.size
    assert_equal [ "a nice logo" ], result.unrecognized
  end
end
