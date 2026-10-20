require "rails_helper"

RSpec.describe Condition do
  def condition(**attrs) = described_class.new(screen: Screen.new, **attrs).tap(&:validate)

  # A year+ of steadily rising prices with a volume spike on the last day.
  def rising_series(days: 300)
    start = Date.new(2024, 1, 1)
    PriceSeries.new((0...days).map do |i|
      close = 100.0 + i
      PriceSeries::Point.new(date: start + i, open: close - 0.5, high: close + 1, low: close - 1, close: close,
                             volume: i == days - 1 ? 3_000 : 1_000)
    end)
  end

  describe "the whitelist" do
    it "accepts a condition that fits SPECS" do
      expect(condition(indicator: "rsi", operator: "below", value: 30)).to be_valid
    end

    it "rejects anything outside it" do
      expect(condition(indicator: "astrology", operator: "below", value: 30)).not_to be_valid
      expect(condition(indicator: "rsi", operator: "crosses_up", value: 30)).not_to be_valid
      expect(condition(indicator: "rsi", operator: "below", value: 300)).not_to be_valid
      expect(condition(indicator: "rsi", operator: "below")).not_to be_valid
      expect(condition(indicator: "sma", operator: "above", period: 1000)).not_to be_valid
      expect(condition(indicator: "price", operator: "above", value: 5, timeframe: "hourly")).not_to be_valid
    end

    it "fills in defaults and clears fields that don't apply" do
      volume = condition(indicator: "volume", operator: "above")
      expect([ volume.period, volume.value, volume.timeframe ]).to eq [ 20, 1.0, "daily" ]

      macd = condition(indicator: "macd", operator: "crosses_up", period: 5, value: 3)
      expect(macd).to be_valid
      expect(macd).to have_attributes(period: nil, value: nil)
    end
  end

  describe "#label" do
    it "reads like the screen" do
      expect(condition(indicator: "rsi", operator: "below", value: 30).label).to eq "RSI(14) below 30"
      expect(condition(indicator: "sma", operator: "above", period: 200, timeframe: "weekly").label)
        .to eq "Price above SMA(200) (weekly)"
    end
  end

  describe "#evaluate" do
    let(:series) { rising_series }

    it "evaluates RSI, moving averages, drawdown and price" do
      expect(condition(indicator: "rsi", operator: "above", value: 90).evaluate(series).passed).to be true
      expect(condition(indicator: "sma", operator: "above", period: 200).evaluate(series).passed).to be true
      expect(condition(indicator: "ema", operator: "below", period: 20).evaluate(series).passed).to be false
      expect(condition(indicator: "drawdown", operator: "below", value: 5).evaluate(series).passed).to be true
      expect(condition(indicator: "price", operator: "above", value: 300).evaluate(series).passed).to be true
    end

    it "compares volume to its prior average and scores how far past the threshold it is" do
      result = condition(indicator: "volume", operator: "above", value: 2.5).evaluate(series)
      expect(result).to have_attributes(passed: true, reason: "volume 3x its 20-bar avg")
      expect(result.strength).to be_within(1e-9).of(0.2) # 3x vs a 2.5x threshold: 20% past it
    end

    it "never passes without enough history" do
      result = condition(indicator: "sma", operator: "above", period: 200).evaluate(rising_series(days: 50))
      expect(result).to have_attributes(passed: false, observed: "n/a", strength: 0.0)
    end

    context "with a MACD cross after a sell-off and a bounce" do
      let(:series) do
        closes = Array.new(60) { |i| 100.0 - i * i * 0.01 } + [ 72, 75, 79 ]
        PriceSeries.new(closes.each_with_index.map do |c, i|
          PriceSeries::Point.new(date: Date.new(2024, 1, 1) + i, open: c, high: c, low: c, close: c, volume: 1)
        end)
      end

      it "detects the cross up and scores fresher crosses higher" do
        result = condition(indicator: "macd", operator: "crosses_up").evaluate(series)
        expect(result).to have_attributes(passed: true, reason: "MACD crossed up 1 bar ago")
        expect(result.strength).to be_within(1e-9).of(2.0 / 3)
      end

      it "does not report a cross down" do
        expect(condition(indicator: "macd", operator: "crosses_down").evaluate(series).passed).to be false
      end
    end
  end
end
