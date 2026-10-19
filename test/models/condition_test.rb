require "test_helper"

class ConditionTest < ActiveSupport::TestCase
  # A year+ of steadily rising prices with a volume spike on the last day.
  def rising_series(days: 300)
    start = Date.new(2024, 1, 1)
    PriceSeries.new((0...days).map do |i|
      close = 100.0 + i
      PriceSeries::Point.new(date: start + i, open: close - 0.5, high: close + 1, low: close - 1, close: close,
                             volume: i == days - 1 ? 3_000 : 1_000)
    end)
  end

  def condition(**attrs) = Condition.new(screen: Screen.new, **attrs)

  test "whitelist validations" do
    assert condition(indicator: "rsi", operator: "below", value: 30).valid?
    refute condition(indicator: "astrology", operator: "below", value: 30).valid?
    refute condition(indicator: "rsi", operator: "crosses_up", value: 30).valid?
    refute condition(indicator: "rsi", operator: "below", value: 300).valid?
    refute condition(indicator: "rsi", operator: "below").valid?
    refute condition(indicator: "sma", operator: "above", period: 1000).valid?
    refute condition(indicator: "price", operator: "above", value: 5, timeframe: "hourly").valid?
  end

  test "defaults fill in period, volume multiplier and timeframe; irrelevant fields are cleared" do
    c = condition(indicator: "volume", operator: "above")
    assert c.valid?
    assert_equal [ 20, 1.0, "daily" ], [ c.period, c.value, c.timeframe ]

    macd = condition(indicator: "macd", operator: "crosses_up", period: 5, value: 3)
    assert macd.valid?
    assert_nil macd.period
    assert_nil macd.value
  end

  test "labels" do
    assert_equal "RSI(14) below 30", condition(indicator: "rsi", operator: "below", value: 30).tap(&:validate).label
    assert_equal "Price above SMA(200) (weekly)", condition(indicator: "sma", operator: "above", period: 200, timeframe: "weekly").label
  end

  test "evaluates rsi, moving averages, volume, drawdown and price on a rising series" do
    series = rising_series
    assert condition(indicator: "rsi", operator: "above", value: 90).tap(&:validate).evaluate(series).passed
    assert condition(indicator: "sma", operator: "above", period: 200).evaluate(series).passed
    refute condition(indicator: "ema", operator: "below", period: 20).evaluate(series).passed
    assert condition(indicator: "drawdown", operator: "below", value: 5).evaluate(series).passed
    assert condition(indicator: "price", operator: "above", value: 300).evaluate(series).passed

    volume = condition(indicator: "volume", operator: "above", value: 2.5).tap(&:validate).evaluate(series)
    assert volume.passed
    assert_equal "volume 3x its 20-bar avg", volume.reason
    assert_in_delta 0.2, volume.strength, 1e-9 # 3x vs a 2.5x threshold: 20% past it
  end

  test "not enough history never passes" do
    result = condition(indicator: "sma", operator: "above", period: 200).evaluate(rising_series(days: 50))
    refute result.passed
    assert_equal "n/a", result.observed
    assert_equal 0.0, result.strength
  end

  test "macd cross up after a dip and recovery" do
    start = Date.new(2024, 1, 1)
    closes = Array.new(60) { |i| 100.0 - i * i * 0.01 } + [ 72, 75, 79 ] # accelerating sell-off, then a bounce
    series = PriceSeries.new(closes.each_with_index.map { |c, i| PriceSeries::Point.new(date: start + i, open: c, high: c, low: c, close: c, volume: 1) })

    result = condition(indicator: "macd", operator: "crosses_up").evaluate(series)
    assert result.passed
    assert_equal "MACD crossed up 1 bar ago", result.reason
    assert_in_delta 2.0 / 3, result.strength, 1e-9 # fresher crosses rank higher
    refute condition(indicator: "macd", operator: "crosses_down").evaluate(series).passed
  end
end
