require "rails_helper"

RSpec.describe MarketData::Yahoo do
  let(:chart_json) { file_fixture("aapl_chart.json").read }
  let(:chart_url) { %r{\Ahttps://query1\.finance\.yahoo\.com/v8/finance/chart/AAPL\?} }

  describe ".fetch" do
    it "requests two years of daily bars and parses them" do
      stub = stub_request(:get, chart_url)
        .with(query: { "range" => "2y", "interval" => "1d" })
        .to_return(status: 200, body: chart_json, headers: { "Content-Type" => "application/json" })

      rows = described_class.fetch("AAPL")

      expect(stub).to have_been_requested
      expect(rows.map { |r| r[:date] }).to eq [ Date.new(2026, 10, 15), Date.new(2026, 10, 16) ]
    end

    it "turns an HTTP error into a MarketData::Error" do
      stub_request(:get, chart_url).to_return(status: 404, body: "Not Found")
      expect { described_class.fetch("AAPL") }.to raise_error(MarketData::Error, /HTTP 404/)
    end

    it "turns a timeout into a MarketData::Error" do
      stub_request(:get, chart_url).to_timeout
      expect { described_class.fetch("AAPL") }.to raise_error(MarketData::Error, /unreachable/)
    end
  end

  describe ".parse" do
    it "reads the chart API in exchange-local dates, skipping empty days" do
      rows = described_class.parse(chart_json, "AAPL")
      expect(rows.size).to eq 2
      expect(rows.first).to eq(date: Date.new(2026, 10, 15), open: 247.1, high: 249.5, low: 246.2, close: 248.9, volume: 51_234_567)
    end

    it "raises MarketData::Error for API errors and non-JSON" do
      expect { described_class.parse('{"chart":{"result":null,"error":{"code":"Not Found"}}}', "NOPE") }.to raise_error(MarketData::Error)
      expect { described_class.parse("<html>", "NOPE") }.to raise_error(MarketData::Error)
    end
  end
end
