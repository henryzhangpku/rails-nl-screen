require "rails_helper"

RSpec.describe ScreenParser do
  def parse(text) = described_class.parse(text)
  def first(text) = parse(text).conditions.first
  def reason(text) = parse(text).unmapped.first&.fetch(:reason)

  it "turns EquityScout's daily-and-weekly example into its spec" do
    result = parse("RSI under 30 on the daily, MACD crossing above its signal on the weekly, volume above its 20-day average")

    expect(result.conditions).to eq [
      { field: "rsi14", op: "<", value: 30 },
      { field: "macd_cross_up_w", op: "==", value: true },
      { field: "volume_ratio_20d", op: ">", value: 1 }
    ]
    expect(result.unmapped).to be_empty
  end

  describe "RSI" do
    it "reads comparisons, the weekly timeframe and the oversold/overbought shorthands" do
      expect(first("rsi > 70")).to eq(field: "rsi14", op: ">", value: 70)
      expect(first("weekly RSI above 60")).to eq(field: "rsi14_w", op: ">", value: 60)
      expect(first("oversold")).to eq(field: "rsi14", op: "<", value: 30)
      expect(first("overbought names")[:op]).to eq ">"
    end

    it "refuses a period other than 14, which has no field" do
      expect(reason("RSI 7 below 25")).to eq "only RSI(14) is computed (daily rsi14 and weekly rsi14_w), not RSI(7)"
    end
  end

  describe "MACD" do
    it "reads a cross up, and MACD above its signal" do
      expect(first("macd crosses above signal")).to eq(field: "macd_cross_up", op: "==", value: true)
      expect(first("MACD above its signal")).to eq(field: "macd_hist", op: ">", value: 0)
    end

    it "refuses a cross down, which has no field" do
      expect(parse("MACD bearish cross").conditions).to be_empty
      expect(reason("MACD bearish cross")).to start_with "there is no field for a MACD cross down"
    end
  end

  describe "volume" do
    it "reads a multiplier against the 20- or 50-day average" do
      expect(first("volume 2x its 50-day average")).to eq(field: "volume_ratio_50d", op: ">", value: 2)
      expect(first("volume below its 20-day average")).to eq(field: "volume_ratio_20d", op: "<", value: 1)
      expect(reason("volume above the 10-day average")).to eq "volume is compared with its 20- or 50-day average only, not 10 days"
    end
  end

  describe "moving averages" do
    it "compares the price with the 20-, 50- or 200-day average" do
      expect(first("price above the 200-day moving average")).to eq(field: "close", op: ">", ref: "sma200")
      expect(first("below SMA(50)")).to eq(field: "close", op: "<", ref: "sma50")
      expect(first("golden cross")).to eq(field: "sma50_above_sma200", op: "==", value: true)
    end

    it "refuses an EMA, a weekly average and other periods" do
      expect(reason("price below the 21 day EMA")).to start_with "there is no EMA field"
      expect(reason("above the 30-week moving average")).to eq "moving averages are daily only (20-, 50- and 200-day)"
      expect(reason("above the 100-day moving average")).to eq "only the 20-, 50- and 200-day averages are computed, not 100 days"
    end
  end

  describe "drawdown from the 52-week high, as a decimal ratio" do
    it "reads 'within' as >= -x and 'down at least' as <= -x" do
      expect(first("within 5% of the 52-week high")).to eq(field: "drawdown_52w", op: ">=", value: -0.05)
      expect(first("down at least 25% from its 52 week high")).to eq(field: "drawdown_52w", op: "<=", value: -0.25)
      expect(first("near the 52-week high")[:value]).to eq(-0.05)
    end
  end

  describe "price and returns" do
    it "keeps 'between X and Y' together as one condition" do
      expect(parse("price between $20 and $100").conditions).to eq [ { field: "close", op: "between", value: [ 20, 100 ] } ]
      expect(first("trading under $50")).to eq(field: "close", op: "<", value: 50)
    end

    it "reads returns over 1, 3, 6 or 12 months" do
      expect(first("up over the last 3 months")).to eq(field: "mom_3m", op: ">", value: 0)
      expect(first("6-month return above 10%")).to eq(field: "mom_6m", op: ">", value: 0.1)
    end
  end

  it "recognizes fields this demo doesn't compute, and refuses them with the contract's reason" do
    expect(reason("revenue growing over 10%")).to eq "Revenue growth (year over year) needs financial statements (SEC filings), which this demo doesn't load"
    expect(reason("high short interest")).to eq "Short interest (% of shares) needs FINRA short interest, which this demo doesn't load"
    expect(reason("lagging the S&P over 3 months")).to start_with "3-month return vs the S&P 500 (SPY) needs benchmark ETF prices"
  end

  it "reports anything else as unmapped, with a reason, and ignores filler words" do
    result = parse("show me stocks with RSI under 30 and a nice logo")
    expect(result.conditions.size).to eq 1
    expect(result.unmapped).to eq [ { text: "a nice logo", reason: "no rule matches this" } ]
  end
end
