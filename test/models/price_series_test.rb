require "test_helper"

class PriceSeriesTest < ActiveSupport::TestCase
  test "weekly resampling" do
    monday = Date.new(2026, 10, 5)
    days = (0..6).map { |i| monday + i }.reject { |d| d.saturday? || d.sunday? } + [ monday + 7 ]
    series = PriceSeries.new(days.each_with_index.map do |d, i|
      PriceSeries::Point.new(date: d, open: 10 + i, high: 20 + i, low: 5 - i, close: 15 + i, volume: 100)
    end)

    weekly = series.weekly
    assert_equal 2, weekly.size
    first = weekly.points.first
    assert_equal [ monday + 4, 10, 24, 1, 19, 500 ], [ first.date, first.open, first.high, first.low, first.close, first.volume ]
  end
end
