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
    it "is seeded with the first value, then smoothed (pandas ewm, adjust=False)" do
      # k = 2 / (3 + 1) = 0.5: 1, 1.5, 2.25, 3.125
      expect(described_class.ema([ 1, 2, 3, 4 ], 3)).to eq [ 1.0, 1.5, 2.25, 3.125 ]
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

    it "is 100 when price only rises, and 50 when it doesn't move" do
      expect(described_class.rsi((1..20).to_a, 14).last).to eq 100.0
      expect(described_class.rsi([ 10 ] * 20, 14).last).to eq 50.0
    end
  end

  describe ".macd" do
    let(:closes) { (1..60).map { |i| 100 + Math.sin(i / 5.0) * 10 } }
    subject(:macd) { described_class.macd(closes) }

    it "is the fast EMA minus the slow EMA, from the first bar" do
      fast = described_class.ema(closes, 12)
      slow = described_class.ema(closes, 26)
      expect(macd[:line][0]).to eq 0.0
      expect(macd[:line][40]).to be_within(1e-9).of(fast[40] - slow[40])
    end

    it "has a histogram of line minus signal" do
      expect(macd[:histogram][50]).to be_within(1e-9).of(macd[:line][50] - macd[:signal][50])
    end
  end

  it "computes momentum, volume ratio and drawdown like EquityScout" do
    expect(described_class.momentum([ 100, 110, 121 ], 2)).to eq [ nil, nil, 121 / 100.0 - 1 ]
    expect(described_class.volume_ratio([ 10, 20, 30, 40 ], 2)).to eq [ nil, nil, 2.0, 40 / 25.0 ] # today vs the prior 2
    expect(described_class.drawdown_from_high([ 10, 20, 15 ], 2)).to eq [ nil, 0.0, -0.25 ]
  end

  describe ".crossed_above" do
    it "is true only when the histogram goes from <= 0 to > 0 on the last bar" do
      expect(described_class.crossed_above([ -1, 0, 0.5 ])).to be true
      expect(described_class.crossed_above([ -1, 0.5, 1 ])).to be false
      expect(described_class.crossed_above([ 0.5 ])).to be_nil
    end
  end
end
