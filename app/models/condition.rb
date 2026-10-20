# One typed, whitelisted rule of a Screen, e.g. "RSI(14) below 30 on the daily".
#
# SPECS is the whitelist: whatever the parser (or Claude) proposes must fit it,
# or validation fails and the condition is dropped.
# == Schema Information
#
# Table name: conditions
# Database name: primary
#
#  id         :integer          not null, primary key
#  indicator  :string           not null
#  operator   :string           not null
#  period     :integer
#  position   :integer          default(0), not null
#  timeframe  :string           default("daily"), not null
#  value      :float
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  screen_id  :integer          not null
#
# Indexes
#
#  index_conditions_on_screen_id  (screen_id)
#
# Foreign Keys
#
#  screen_id  (screen_id => screens.id)
#
class Condition < ApplicationRecord
  belongs_to :screen

  SPECS = {
    "rsi"      => { name: "RSI",              operators: %w[below above],        period: 14,  value: 0..100 },
    "macd"     => { name: "MACD",             operators: %w[crosses_up crosses_down] },
    "sma"      => { name: "SMA",              operators: %w[above below],        period: 50 },
    "ema"      => { name: "EMA",              operators: %w[above below],        period: 20 },
    "volume"   => { name: "Volume",           operators: %w[above below],        period: 20,  value: 0.1..20 },
    "drawdown" => { name: "Drawdown from 52-week high", operators: %w[above below], value: 0..100 },
    "price"    => { name: "Price",            operators: %w[above below],        value: 0.01..1_000_000 }
  }.freeze
  TIMEFRAMES = %w[daily weekly].freeze
  PERIODS = 2..250
  MACD_CROSS_LOOKBACK = 3 # "crossing up" = crossed within the last 3 bars

  # strength: how decisively it passed, 0..1 (used to rank matches). For a
  # threshold it's the distance past the threshold as a fraction of it, capped
  # at 1; for a MACD cross, fresher crosses score higher.
  Evaluation = Data.define(:passed, :observed, :reason, :strength)

  before_validation :apply_defaults
  validates :indicator, inclusion: { in: SPECS.keys }
  validates :timeframe, inclusion: { in: TIMEFRAMES }
  validate :fits_spec, if: :spec

  def spec = SPECS[indicator]

  def label
    case indicator
    when "rsi"      then "RSI(#{period}) #{operator} #{fmt(value)}"
    when "macd"     then "MACD #{operator == "crosses_up" ? "crosses above" : "crosses below"} signal"
    when "sma", "ema" then "Price #{operator} #{spec[:name]}(#{period})"
    when "volume"   then "Volume #{operator} #{fmt(value)}x its #{period}-bar average"
    when "drawdown" then "Drawdown from 52-week high #{operator} #{fmt(value)}%"
    when "price"    then "Price #{operator} $#{fmt(value)}"
    end + (timeframe == "weekly" ? " (weekly)" : "")
  end

  # Runs this rule against a PriceSeries (already in the right timeframe).
  def evaluate(series)
    closes = series.closes
    close = closes.last

    case indicator
    when "rsi"
      rsi = Indicators.rsi(closes, period).last
      return insufficient unless rsi
      compare(rsi, "RSI(#{period}) #{fmt(rsi)}", "RSI(#{period}) #{fmt(rsi)} #{symbol} #{fmt(value)}")
    when "macd"
      macd = Indicators.macd(closes)
      direction = operator == "crosses_up" ? :up : :down
      ago = Indicators.bars_since_cross(macd[:line], macd[:signal], direction: direction, within: MACD_CROSS_LOOKBACK)
      hist = macd[:histogram].last
      return insufficient unless hist
      observed = "hist #{fmt(hist, 3)}"
      reason = ago && "MACD crossed #{direction} #{ago.zero? ? "on the last bar" : "#{ago} bar#{"s" if ago > 1} ago"}"
      strength = ago ? (MACD_CROSS_LOOKBACK - ago).fdiv(MACD_CROSS_LOOKBACK) : 0.0
      Evaluation.new(!ago.nil?, observed, reason, strength)
    when "sma", "ema"
      ma = Indicators.public_send(indicator, closes, period).last
      return insufficient unless ma
      pct = (close / ma - 1) * 100
      compare(close, "close #{fmt(close)} vs #{fmt(ma)}",
              "close #{fmt(pct.abs, 1)}% #{pct >= 0 ? "above" : "below"} #{spec[:name]}#{period}", against: ma)
    when "volume"
      prior = series.volumes[-(period + 1)...-1]
      return insufficient unless prior && prior.size == period
      ratio = series.volumes.last / (prior.sum.to_f / period)
      compare(ratio, "#{fmt(ratio)}x avg", "volume #{fmt(ratio, 1)}x its #{period}-bar avg")
    when "drawdown"
      high = series.highs_since(1.year.before(series.dates.last)).max
      dd = (1 - close / high) * 100
      compare(dd, "#{fmt(dd, 1)}% off high", "#{fmt(dd, 1)}% below 52-week high #{fmt(high)}")
    when "price"
      compare(close, "$#{fmt(close)}", "price $#{fmt(close)} #{symbol} $#{fmt(value)}")
    end
  end

  private
    def apply_defaults
      return unless spec
      self.period ||= spec[:period]
      self.period = nil unless spec[:period]
      self.value ||= 1.0 if indicator == "volume"
      self.value = nil unless spec[:value]
      self.timeframe ||= "daily"
    end

    def fits_spec
      errors.add(:operator, "is not allowed for #{indicator}") unless spec[:operators].include?(operator)
      errors.add(:period, "must be between #{PERIODS.min} and #{PERIODS.max}") if spec[:period] && !PERIODS.cover?(period)
      errors.add(:value, "must be in #{spec[:value]}") if spec[:value] && !(value && spec[:value].cover?(value))
    end

    def compare(left, observed, reason, against: value)
      passed = operator == "above" ? left > against : left < against
      strength = passed ? [ (left - against).abs / against.abs, 1.0 ].min : 0.0
      Evaluation.new(passed, observed, reason, strength)
    end

    def symbol = operator == "above" ? ">" : "<"

    def insufficient = Evaluation.new(false, "n/a", nil, 0.0)

    def fmt(number, digits = 2)
      number.to_f.round(digits).to_s.sub(/\.0\z/, "")
    end
end
