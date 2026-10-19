require "test_helper"

class MarketData::YahooTest < ActiveSupport::TestCase
  test "parses the chart api, in exchange-local dates, skipping empty days" do
    rows = MarketData::Yahoo.parse(file_fixture("aapl_chart.json").read, "AAPL")
    assert_equal 2, rows.size
    assert_equal({ date: Date.new(2026, 10, 15), open: 247.1, high: 249.5, low: 246.2, close: 248.9, volume: 51_234_567 }, rows.first)
    assert_equal Date.new(2026, 10, 16), rows.last[:date]
  end

  test "errors and non-json are a MarketData::Error" do
    assert_raises(MarketData::Error) { MarketData::Yahoo.parse('{"chart":{"result":null,"error":{"code":"Not Found"}}}', "NOPE") }
    assert_raises(MarketData::Error) { MarketData::Yahoo.parse("<html>", "NOPE") }
  end
end
