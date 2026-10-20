require "rails_helper"

RSpec.describe ScreenParser do
  def parse(text) = described_class.parse(text)
  def first(text) = parse(text).conditions.first

  it "turns the representative query into four conditions" do
    result = parse("RSI(14) under 30 on the daily, MACD crossing up, volume above its 20-day average, price above the 200-day moving average")

    expect(result.conditions).to eq [
      { indicator: "rsi", period: 14, operator: "below", value: 30.0, timeframe: "daily" },
      { indicator: "macd", operator: "crosses_up", timeframe: "daily" },
      { indicator: "volume", period: 20, operator: "above", value: nil, timeframe: "daily" },
      { indicator: "sma", period: 200, operator: "above", timeframe: "daily" }
    ]
    expect(result.unrecognized).to be_empty
  end

  describe "RSI" do
    it "reads comparisons, periods and the oversold/overbought shorthands" do
      expect(first("rsi > 70")).to eq(indicator: "rsi", period: nil, operator: "above", value: 70.0, timeframe: "daily")
      expect(first("RSI 7 below 25")[:period]).to eq 7
      expect(first("oversold")).to eq(indicator: "rsi", period: nil, operator: "below", value: 30.0, timeframe: "daily")
      expect(first("overbought names")[:operator]).to eq "above"
    end
  end

  describe "MACD" do
    it "reads the cross direction" do
      expect(first("MACD bearish cross")[:operator]).to eq "crosses_down"
      expect(first("macd crosses above signal")[:operator]).to eq "crosses_up"
    end
  end

  describe "volume" do
    it "reads a multiplier and a period" do
      expect(first("volume 2x its 50-day average")).to eq(indicator: "volume", period: 50, operator: "above", value: 2.0, timeframe: "daily")
      expect(first("volume below the 10-day average")[:operator]).to eq "below"
    end
  end

  describe "moving averages" do
    it "reads SMA vs EMA, the period and the side" do
      expect(first("price below the 21 day EMA")).to eq(indicator: "ema", period: 21, operator: "below", timeframe: "daily")
      expect(first("above SMA(50)")).to eq(indicator: "sma", period: 50, operator: "above", timeframe: "daily")
    end
  end

  describe "drawdown from the 52-week high" do
    it "reads 'within' as below and 'down at least' as above" do
      expect(first("within 5% of the 52-week high")).to eq(indicator: "drawdown", operator: "below", value: 5.0, timeframe: "daily")
      expect(first("down at least 25% from its 52 week high")).to eq(indicator: "drawdown", operator: "above", value: 25.0, timeframe: "daily")
      expect(first("near the 52-week high")[:value]).to eq 5.0
    end
  end

  describe "price" do
    it "keeps 'between X and Y' together and makes two conditions" do
      expect(parse("price between $20 and $100").conditions).to eq [
        { indicator: "price", operator: "above", value: 20.0, timeframe: "daily" },
        { indicator: "price", operator: "below", value: 100.0, timeframe: "daily" }
      ]
      expect(first("trading under $50")).to eq(indicator: "price", operator: "below", value: 50.0, timeframe: "daily")
    end
  end

  it "applies the weekly timeframe per clause" do
    conditions = parse("weekly RSI above 60, price above the 30-week moving average").conditions
    expect(conditions.map { |c| c[:timeframe] }).to eq %w[weekly daily]
  end

  it "reports unknown clauses and ignores filler words" do
    result = parse("show me stocks with RSI under 30 and a nice logo")
    expect(result.conditions.size).to eq 1
    expect(result.unrecognized).to eq [ "a nice logo" ]
  end
end
