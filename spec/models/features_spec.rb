require "rails_helper"

# Parity with EquityScout, the Python version of this product: the fixture holds daily
# bars and the values EquityScout's snapshot() computes from them (its "source" says
# which commit). Every field this demo computes must match, including where there's
# too little history (nil in both).
RSpec.describe Features do
  fixture = JSON.parse(Rails.root.join("spec/fixtures/files/equity_scout_features.json").read)

  fixture["series"].each do |series|
    it "matches EquityScout for #{series["symbol"]} (#{series["close"].size} bars)" do
      bars = series["dates"].each_index.map do |i|
        close = series["close"][i]
        PriceSeries::Point.new(date: Date.parse(series["dates"][i]), open: close, high: close, low: close, close: close,
                               volume: series["volume"][i])
      end
      features = described_class.for(PriceSeries.new(bars))

      series["expected"].each do |field, expected|
        actual = features[field]
        if expected.nil? || expected.in?([ true, false ])
          expect(actual).to eq(expected), "#{field}: expected #{expected.inspect}, got #{actual.inspect}"
        else
          expect(actual).to be_within(1e-9 * [ 1, expected.abs ].max).of(expected), "#{field}: expected #{expected}, got #{actual.inspect}"
        end
      end
    end
  end

  it "covers every field the screen spec says this demo computes" do
    expect(fixture["series"].first["expected"].keys).to match_array ScreenSpec::AVAILABLE
  end

  it "has nothing without bars" do
    expect(described_class.for(PriceSeries.new([]))).to eq({})
  end
end
