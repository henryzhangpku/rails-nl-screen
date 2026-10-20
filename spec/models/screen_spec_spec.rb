require "rails_helper"

# The contract shared with EquityScout: its wording and its validation messages are
# checked here against the ones in EquityScout (docs/ui.js plainCond, spec.validate).
RSpec.describe ScreenSpec do
  describe ".describe" do
    {
      { field: "drawdown_52w", op: "<=", value: -0.2 }      => "Down at least 20% from 52-week high",
      { field: "drawdown_52w", op: ">=", value: -0.05 }     => "Within 5% of 52-week high",
      { field: "close", op: ">", ref: "sma200" }            => "Price above its 200-day average",
      { field: "pct_vs_sma50", op: ">", value: 0.1 }        => "Price at least 10% above its 50-day average",
      { field: "volume_ratio_20d", op: ">", value: 1 }      => "Volume above its 20-day average",
      { field: "volume_ratio_50d", op: ">", value: 1.5 }    => "Volume at least 1.5× its 50-day average",
      { field: "rsi14", op: "<", value: 30 }                => "Daily RSI (14) under 30",
      { field: "rsi14_w", op: "<", value: 45 }              => "Weekly RSI (14) under 45",
      { field: "macd_cross_up_w", op: "==", value: true }   => "Weekly MACD crossed above its signal this week",
      { field: "sma50_above_sma200", op: "==", value: true } => "50-day average above 200-day average (uptrend)",
      { field: "mom_3m", op: ">", value: 0 }                => "Price up over 3 months",
      { field: "rs_3m_vs_smh", op: "<", value: 0 }          => "Lagging the chip index (SMH) over 3 months",
      { field: "close", op: "between", value: [ 20, 200 ] } => "Price between $20 and $200",
      { field: "market_cap", op: ">=", value: 2e9 }         => "Market cap ≥ $2B",
      { field: "revenue_growth_yoy", op: ">", value: 0.1 }  => "Revenue growth (year over year) > 10%"
    }.each do |condition, text|
      it("reads #{condition.values_at(:field, :op).join(" ")} as \"#{text}\"") { expect(described_class.describe(condition)).to eq text }
    end
  end

  describe ".condition_problems" do
    def problems(c) = described_class.condition_problems(c.stringify_keys)

    it "is empty for a valid condition" do
      expect(problems(field: "rsi14", op: "<", value: 30)).to eq []
    end

    it "uses EquityScout's messages" do
      expect(problems(field: "rsi14", op: "<", value: 30, ref: "rsi14_w"))
        .to eq [ "condition: give exactly one of 'value' (a threshold) or 'ref' (another field)" ]
      expect(problems(field: "close", op: "between", value: [ 200, 20 ])).to eq [ "condition: 'between' needs value [low, high] with low < high" ]
      expect(problems(field: "rsi14", op: "==", value: 30)).to eq [ "condition: '==' is only for boolean fields" ]
      expect(problems(field: "close", op: ">", ref: "rsi14")).to eq [ "condition: cannot compare 'close' (usd) with 'rsi14' (number)" ]
      expect(problems(field: "rsi14", op: "<", value: 30, colour: "red")).to eq [ "condition: unknown key 'colour' (allowed: field, op, ref, value, why)" ]
    end
  end

  it "checks a condition against features: pass, fail, or missing data" do
    features = { "close" => 50.0, "sma200" => 40.0, "macd_cross_up" => false }
    expect(described_class.check({ field: "close", op: "between", value: [ 20, 60 ] }, features)).to eq :pass
    expect(described_class.check({ field: "macd_cross_up", op: "==", value: true }, features)).to eq :fail
    expect(described_class.check({ field: "rsi14", op: "<", value: 30 }, features)).to eq :missing
  end

  describe ".default_rank" do
    it "ranks by each threshold's field in its direction, and by distance above a moving average" do
      expect(described_class.default_rank([ { "field" => "rsi14", "op" => "<", "value" => 30 },
                                            { "field" => "close", "op" => ">", "ref" => "sma200" },
                                            { "field" => "macd_cross_up", "op" => "==", "value" => true } ]))
        .to eq [ { "field" => "rsi14", "direction" => "asc", "weight" => 1 },
                 { "field" => "pct_vs_sma200", "direction" => "desc", "weight" => 1 } ]
    end

    it "falls back to liquidity when there's nothing to rank by" do
      expect(described_class.default_rank([ { "field" => "macd_cross_up", "op" => "==", "value" => true } ]))
        .to eq [ { "field" => "avg_dollar_volume_50d", "direction" => "desc", "weight" => 1 } ]
    end
  end

  # pandas: x.rank(pct=True, method="average"), NaN -> 0, weighted mean across rank keys.
  it "scores like EquityScout's percentile ranking" do
    rows = [ [ "A", { "rsi14" => 20.0, "mom_3m" => 0.1 } ], [ "B", { "rsi14" => 25.0, "mom_3m" => 0.3 } ],
             [ "C", { "rsi14" => 25.0 } ], [ "D", { "rsi14" => 29.0, "mom_3m" => 0.2 } ] ]
    rank = [ { "field" => "rsi14", "direction" => "asc", "weight" => 2 }, { "field" => "mom_3m", "direction" => "desc", "weight" => 1 } ]
    scores = described_class.scores(rows, rank)

    # rsi14 asc: A 1.0, B and C tie at 0.625, D 0.25; mom_3m desc: B 1.0, D 0.667, A 0.333, C missing 0.
    expect(scores["A"]).to be_within(1e-9).of((2 * 1.0 + 1 / 3.0) / 3)
    expect(scores["B"]).to be_within(1e-9).of((2 * 0.625 + 1.0) / 3)
    expect(scores["C"]).to be_within(1e-9).of((2 * 0.625 + 0) / 3)
    expect(scores["D"]).to be_within(1e-9).of((2 * 0.25 + 2 / 3.0) / 3)
  end
end
