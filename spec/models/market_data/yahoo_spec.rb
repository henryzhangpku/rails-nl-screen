require "rails_helper"

RSpec.describe MarketData::Yahoo do
  describe ".parse" do
    it "reads the chart API in exchange-local dates, skipping empty days" do
      rows = described_class.parse(file_fixture("aapl_chart.json").read, "AAPL")
      expect(rows.size).to eq 2
      expect(rows.first).to eq(date: Date.new(2026, 10, 15), open: 247.1, high: 249.5, low: 246.2, close: 248.9, volume: 51_234_567)
      expect(rows.last[:date]).to eq Date.new(2026, 10, 16)
    end

    it "raises MarketData::Error for API errors and non-JSON" do
      expect { described_class.parse('{"chart":{"result":null,"error":{"code":"Not Found"}}}', "NOPE") }.to raise_error(MarketData::Error)
      expect { described_class.parse("<html>", "NOPE") }.to raise_error(MarketData::Error)
    end
  end
end
