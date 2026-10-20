require "rails_helper"

RSpec.describe Indicators do
  # Wilder RSI worked example (the classic StockCharts table).
  let(:wilder_closes) do
    [ 44.34, 44.09, 44.15, 43.61, 44.33, 44.83, 45.10, 45.42, 45.84, 46.08, 45.89,
      46.03, 45.61, 46.28, 46.28, 46.00, 46.03, 46.41, 46.22, 45.64, 46.21, 46.25,
      45.71, 46.45, 45.78, 45.35, 44.03, 44.18, 44.22, 44.57, 43.42, 42.66, 43.13 ]
  end
  let(:wilder_rsi) do
    [ 70.53, 66.32, 66.55, 69.41, 66.36, 57.97, 62.93, 63.26, 56.06,
      62.38, 54.71, 50.42, 39.99, 41.46, 41.87, 45.46, 37.30, 33.08, 37.77 ]
  end

  describe ".sma" do
    it "averages a sliding window, nil while warming up" do
      expect(described_class.sma([ 1, 2, 3, 4 ], 2)).to eq [ nil, 1.5, 2.5, 3.5 ]
      expect(described_class.sma([ 1, 2, 3 ], 3)).to eq [ nil, nil, 2.0 ]
    end
  end

  describe ".ema" do
    it "is seeded with the SMA, then smoothed" do
      expect(described_class.ema([ 1, 2, 3, 4, 5 ], 3)).to eq [ nil, nil, 2.0, 3.0, 4.0 ]
    end

    it "is all nil with too little data" do
      expect(described_class.ema([ 1, 2 ], 3)).to eq [ nil, nil ]
    end
  end

  describe ".rsi" do
    it "matches Wilder's worked example" do
      rsi = described_class.rsi(wilder_closes, 14)
      expect(rsi.first(14)).to all(be_nil)
      rsi.drop(14).zip(wilder_rsi).each do |actual, expected|
        expect(actual).to be_within(0.1).of(expected) # the published table rounds its intermediate averages
      end
    end

    it "is 100 when price only rises" do
      expect(described_class.rsi((1..20).to_a, 14).last).to eq 100.0
    end
  end

  describe ".macd" do
    let(:closes) { (1..60).map { |i| 100 + Math.sin(i / 5.0) * 10 } }
    subject(:macd) { described_class.macd(closes) }

    it "is the fast EMA minus the slow EMA" do
      fast = described_class.ema(closes, 12)
      slow = described_class.ema(closes, 26)
      expect(macd[:line][24]).to be_nil
      expect(macd[:line][40]).to be_within(1e-9).of(fast[40] - slow[40])
    end

    it "warms the signal line up after slow + signal - 1 bars" do
      expect(macd[:signal][32]).to be_nil
      expect(macd[:signal][33]).not_to be_nil
    end

    it "has a histogram of line minus signal" do
      expect(macd[:histogram][50]).to be_within(1e-9).of(macd[:line][50] - macd[:signal][50])
    end

    it "is positive on a steady uptrend" do
      expect(described_class.macd((1..60).map(&:to_f))[:line].last).to be_within(1e-9).of(7.0) # (26-12)/2 for a slope of 1
    end
  end

  describe ".bars_since_cross" do
    let(:a) { [ 1, 1, 3, 3, 3 ] }
    let(:b) { [ 2, 2, 2, 2, 2 ] }

    it "finds the most recent cross within the window" do
      expect(described_class.bars_since_cross(a, b, direction: :up, within: 3)).to eq 2
      expect(described_class.bars_since_cross([ 3, 1 ], [ 2, 2 ], direction: :down, within: 1)).to eq 0
    end

    it "returns nil outside the window or in the other direction" do
      expect(described_class.bars_since_cross(a, b, direction: :up, within: 2)).to be_nil
      expect(described_class.bars_since_cross(a, b, direction: :down, within: 5)).to be_nil
    end
  end
end
