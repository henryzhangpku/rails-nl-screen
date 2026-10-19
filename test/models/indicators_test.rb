require "test_helper"

class IndicatorsTest < ActiveSupport::TestCase
  # Wilder RSI worked example (the classic StockCharts table).
  WILDER_CLOSES = [
    44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.42, 45.84, 46.08, 45.89,
    46.03, 45.61, 46.28, 46.28, 46.00, 46.03, 46.41, 46.22, 45.64, 46.21, 46.25,
    45.71, 46.45, 45.78, 45.35, 44.03, 44.18, 44.22, 44.57, 43.42, 42.66, 43.13
  ]
  WILDER_RSI = [ 70.53, 66.32, 66.55, 69.41, 66.36, 57.97, 62.93, 63.26, 56.06,
                 62.38, 54.71, 50.42, 39.99, 41.46, 41.87, 45.46, 37.30, 33.08, 37.77 ]

  test "sma" do
    assert_equal [ nil, 1.5, 2.5, 3.5 ], Indicators.sma([ 1, 2, 3, 4 ], 2)
    assert_equal [ nil, nil, 2.0 ], Indicators.sma([ 1, 2, 3 ], 3)
  end

  test "ema is seeded with the sma then smoothed" do
    assert_equal [ nil, nil, 2.0, 3.0, 4.0 ], Indicators.ema([ 1, 2, 3, 4, 5 ], 3)
  end

  test "ema with too little data is all nil" do
    assert_equal [ nil, nil ], Indicators.ema([ 1, 2 ], 3)
  end

  test "rsi matches Wilder's worked example" do
    rsi = Indicators.rsi(WILDER_CLOSES, 14)
    assert_equal Array.new(14), rsi.first(14)
    rsi.drop(14).zip(WILDER_RSI).each do |actual, expected|
      assert_in_delta expected, actual, 0.1 # the published table rounds its intermediate averages
    end
  end

  test "rsi is 100 when price only rises" do
    assert_equal 100.0, Indicators.rsi((1..20).to_a, 14).last
  end

  test "macd line is fast ema minus slow ema, signal warms up after slow+signal-1 bars" do
    closes = (1..60).map { |i| 100 + Math.sin(i / 5.0) * 10 }
    macd = Indicators.macd(closes)
    fast = Indicators.ema(closes, 12)
    slow = Indicators.ema(closes, 26)

    assert_nil macd[:line][24]
    assert_in_delta fast[40] - slow[40], macd[:line][40], 1e-9
    assert_nil macd[:signal][32]
    refute_nil macd[:signal][33]
    assert_in_delta macd[:line][50] - macd[:signal][50], macd[:histogram][50], 1e-9
  end

  test "macd on a steady uptrend is positive" do
    macd = Indicators.macd((1..60).map(&:to_f))
    assert_in_delta 7.0, macd[:line].last, 1e-9 # (26-12)/2 for a slope of 1
  end

  test "bars_since_cross finds the most recent cross within the window" do
    a = [ 1, 1, 3, 3, 3 ]
    b = [ 2, 2, 2, 2, 2 ]
    assert_equal 2, Indicators.bars_since_cross(a, b, direction: :up, within: 3)
    assert_nil Indicators.bars_since_cross(a, b, direction: :up, within: 2)
    assert_nil Indicators.bars_since_cross(a, b, direction: :down, within: 5)
    assert_equal 0, Indicators.bars_since_cross([ 3, 1 ], [ 2, 2 ], direction: :down, within: 1)
  end
end
