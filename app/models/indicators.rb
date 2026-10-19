# Pure functions over arrays of numbers. Each returns an array the same length
# as its input, with nil where there isn't enough history yet ("warm-up").
#
#   Indicators.sma([1, 2, 3, 4], 2)  # => [nil, 1.5, 2.5, 3.5]
module Indicators
  module_function

  # Simple moving average.
  def sma(values, period)
    values.each_index.map do |i|
      next nil if i < period - 1
      values[(i - period + 1)..i].sum.to_f / period
    end
  end

  # Exponential moving average, seeded with the SMA of the first `period` values.
  def ema(values, period)
    k = 2.0 / (period + 1)
    result = Array.new(values.size)
    return result if values.size < period

    result[period - 1] = values.first(period).sum.to_f / period
    (period...values.size).each do |i|
      result[i] = values[i] * k + result[i - 1] * (1 - k)
    end
    result
  end

  # Relative Strength Index with Wilder's smoothing (the textbook definition).
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

  def rsi_from(avg_gain, avg_loss)
    return 100.0 if avg_loss.zero?
    100 - (100 / (1 + avg_gain / avg_loss))
  end

  # MACD line (fast EMA - slow EMA), its signal line (EMA of MACD) and histogram.
  def macd(values, fast: 12, slow: 26, signal: 9)
    fast_ema = ema(values, fast)
    slow_ema = ema(values, slow)
    line = fast_ema.zip(slow_ema).map { |f, s| f && s && f - s }

    first = line.index { |v| v }
    signal_line = Array.new(values.size)
    if first
      ema(line[first..], signal).each_with_index { |v, i| signal_line[first + i] = v }
    end

    histogram = line.zip(signal_line).map { |m, s| m && s && m - s }
    { line: line, signal: signal_line, histogram: histogram }
  end

  # How many bars ago `a` most recently crossed `b` in the given direction
  # (:up = from at-or-below to above), looking back at most `within` bars.
  # Returns 0 for "on the latest bar", nil if no cross in the window.
  def bars_since_cross(a, b, direction:, within:)
    last = a.size - 1
    (0...within).each do |ago|
      i = last - ago
      break if i < 1
      prev_a, prev_b, cur_a, cur_b = a[i - 1], b[i - 1], a[i], b[i]
      next if [ prev_a, prev_b, cur_a, cur_b ].any?(&:nil?)

      crossed = direction == :up ? (prev_a <= prev_b && cur_a > cur_b) : (prev_a >= prev_b && cur_a < cur_b)
      return ago if crossed
    end
    nil
  end
end
