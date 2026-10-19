require "test_helper"

class MarketData::StooqTest < ActiveSupport::TestCase
  test "parses stooq csv" do
    rows = MarketData::Stooq.parse(file_fixture("aapl.csv").read, "AAPL")
    assert_equal 2, rows.size
    assert_equal({ date: Date.new(2026, 10, 16), open: 249.0, high: 251.75, low: 248.1, close: 250.4, volume: 48_765_432 }, rows.last)
  end

  test "non-csv responses are a MarketData::Error" do
    assert_raises(MarketData::Error) { MarketData::Stooq.parse("No data", "NOPE") }
  end
end
