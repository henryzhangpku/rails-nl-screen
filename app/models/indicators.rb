# Pure functions over arrays of numbers. Each returns an array the same length
# as its input, with nil where there isn't enough history yet ("warm-up").
#
# The conventions are EquityScout's (src/scout/indicators.py there), so the same
# prices give the same numbers in both versions of the product:
#
# * SMA(n): arithmetic mean of the last n closes.
# * EMA(span): seeded with the first value, then value * k + previous * (1 - k),
#   k = 2 / (span + 1) (pandas ewm with adjust=False).
# * RSI(n): Wilder's smoothing. The first average gain/loss is the simple mean of
#   the first n changes; afterwards avg = (prev * (n - 1) + current) / n.
# * MACD: EMA(12) - EMA(26) of close, signal = EMA(9) of MACD, histogram = MACD - signal.
# * Momentum over k sessions: close[t] / close[t - k] - 1.
# * Volume ratio: today's volume / mean volume of the previous n sessions.
# * Drawdown from the 52-week high: close / max(close over the last 252 sessions) - 1.
module Indicators
  module_function

  def sma(values, period)
    values.each_index.map do |i|
      next nil if i < period - 1
      values[(i - period + 1)..i].sum.to_f / period
    end
  end

  def ema(values, span)
    k = 2.0 / (span + 1)
    values.each_with_object([]) do |value, result|
      result << (result.empty? ? value.to_f : value * k + result.last * (1 - k))
    end
  end

  def rsi(values, period = 14)
    result = Array.new(values.size)
    return result if values.size <= period

    changes = values.each_cons(2).map { |a, b| b - a }
    avg_gain = changes.first(period).sum { |c| c.positive? ? c : 0 } / period.to_f
    avg_loss = changes.first(period).sum { |c| c.negative? ? -c : 0 } / period.to_f
    result[period] = rsi_from(avg_gain, avg_loss)

    (period...changes.size).each do |i|
      gain = changes[i].positive? ? changes[i] : 0
      loss = changes[i].negative? ? -changes[i] : 0
      avg_gain = (avg_gain * (period - 1) + gain) / period
      avg_loss = (avg_loss * (period - 1) + loss) / period
      result[i + 1] = rsi_from(avg_gain, avg_loss)
    end
    result
  end

  # A flat series (no gains, no losses) is neutral, 50; only gains is 100.
  def rsi_from(avg_gain, avg_loss)
    return avg_gain.positive? ? 100.0 : 50.0 if avg_loss.zero?
    100 - (100 / (1 + avg_gain / avg_loss))
  end

  def macd(values, fast: 12, slow: 26, signal: 9)
    line = ema(values, fast).zip(ema(values, slow)).map { |f, s| f - s }
    signal_line = ema(line, signal)
    { line: line, signal: signal_line, histogram: line.zip(signal_line).map { |m, s| m - s } }
  end

  def momentum(values, k)
    values.each_index.map { |i| i >= k ? values[i] / values[i - k].to_f - 1 : nil }
  end

  def volume_ratio(volumes, period)
    volumes.each_index.map do |i|
      next nil if i < period
      prior = volumes[(i - period)...i].sum.to_f / period
      prior.zero? ? nil : volumes[i] / prior
    end
  end

  def drawdown_from_high(values, period = 252)
    values.each_index.map do |i|
      next nil if i < period - 1
      values[i] / values[(i - period + 1)..i].max.to_f - 1
    end
  end

  # True when the histogram goes from <= 0 on the previous bar to > 0 on the last;
  # nil when that can't be told.
  def crossed_above(histogram)
    previous, last = histogram.last(2)
    return nil if histogram.size < 2 || previous.nil? || last.nil?

    previous <= 0 && last.positive?
  end

  # a > b, with a gap inside rounding counted as a tie, not above (a halted stock's
  # SMA50 can equal its SMA200, and summation order decides the last digit).
  def above?(a, b, rel: 1e-9) = (a - b) > rel * b.abs
end
