require "rails_helper"

RSpec.describe Condition do
  def condition(**attrs) = described_class.new(screen: Screen.new, **attrs).tap(&:validate)

  describe "the contract" do
    it "accepts a whitelisted field with a threshold or a reference field" do
      expect(condition(field: "rsi14", op: "<", value: 30)).to be_valid
      expect(condition(field: "close", op: ">", ref: "sma200")).to be_valid
      expect(condition(field: "macd_cross_up_w", op: "==", value: true)).to be_valid
      expect(condition(field: "close", op: "between", value: [ 20, 200 ])).to be_valid
    end

    it "rejects anything else, with EquityScout's reasons" do
      expect(condition(field: "astrology", op: "<", value: 1).errors.full_messages)
        .to eq [ "unknown field \"astrology\"; it is not in the whitelist of computed fields" ]
      expect(condition(field: "rsi14", op: "<", value: 300).errors.full_messages).to eq [ "rsi14 thresholds must be within 0-100" ]
      expect(condition(field: "drawdown_52w", op: "<=", value: -25).errors.full_messages.first).to match(/looks like a percent/)
      expect(condition(field: "macd_cross_up", op: ">", value: 0)).not_to be_valid
      expect(condition(field: "close", op: ">", value: 5, ref: "sma50")).not_to be_valid
    end

    it "refuses a whitelisted field this demo doesn't compute, and says why" do
      expect(condition(field: "revenue_growth_yoy", op: ">", value: 0.1).errors.full_messages)
        .to eq [ "revenue_growth_yoy needs financial statements (SEC filings), which this demo doesn't load" ]
    end
  end

  it "reads in EquityScout's plain English" do
    expect(condition(field: "rsi14", op: "<", value: 30).label).to eq "Daily RSI (14) under 30"
    expect(condition(field: "close", op: ">", ref: "sma200").label).to eq "Price above its 200-day average"
    expect(condition(field: "drawdown_52w", op: "<=", value: -0.2).label).to eq "Down at least 20% from 52-week high"
  end

  describe "#check and #explain" do
    let(:features) { { "rsi14" => 27.4, "close" => 101.5, "sma200" => 95.0 } }

    it "passes, fails, or reports missing data" do
      expect(condition(field: "rsi14", op: "<", value: 30).check(features)).to eq :pass
      expect(condition(field: "rsi14", op: ">", value: 30).check(features)).to eq :fail
      expect(condition(field: "close", op: ">", ref: "sma50").check(features)).to eq :missing
    end

    it "explains a match with the observed values" do
      expect(condition(field: "rsi14", op: "<", value: 30).explain(features)).to eq "Daily RSI (14) under 30: 27.4"
      expect(condition(field: "close", op: ">", ref: "sma200").explain(features)).to eq "Price above its 200-day average: $101.5 vs $95"
    end
  end
end
