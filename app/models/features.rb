# Every field of the screen spec this demo can compute, for one symbol, from its
# daily bars: the same values EquityScout's snapshot() computes from the same bars.
# A field is nil when there isn't enough history; the screen reports that as
# "missing data", never as a pass or a fail.
module Features
  MIN_WEEKLY_MACD = 35 # slow EMA (26) + signal EMA (9) weeks before a weekly MACD value is used

  module_function

  def for(series)
    closes, volumes = series.closes.map(&:to_f), series.volumes.map(&:to_f)
    return {} if closes.empty?

    close = closes.last
    features = { "close" => close }
    [ 20, 50, 200 ].each do |n|
      sma = Indicators.sma(closes, n).last
      features["sma#{n}"] = sma
      features["pct_vs_sma#{n}"] = sma && close / sma - 1
    end
    sma50, sma200 = features.values_at("sma50", "sma200")
    features["sma50_above_sma200"] = Indicators.above?(sma50, sma200) if sma50 && sma200
    features["rsi14"] = Indicators.rsi(closes, 14).last

    macd = Indicators.macd(closes)
    features["macd"], features["macd_signal"], features["macd_hist"] = macd.values_at(:line, :signal, :histogram).map(&:last)
    features["macd_cross_up"] = Indicators.crossed_above(macd[:histogram])

    ScreenSpec::MONTH_DAYS.each { |m, k| features["mom_#{m}m"] = Indicators.momentum(closes, k).last }
    features["volume_ratio_50d"] = Indicators.volume_ratio(volumes, 50).last
    features["volume_ratio_20d"] = Indicators.volume_ratio(volumes, 20).last
    features["drawdown_52w"] = Indicators.drawdown_from_high(closes).last
    dollar_volumes = closes.zip(volumes).last(50).map { |c, v| c * v }
    features["avg_dollar_volume_50d"] = dollar_volumes.sum / 50 if dollar_volumes.size == 50

    features.merge(weekly(series.weekly.closes.map(&:to_f))).compact
  end

  # Weekly closes: the last close of each week (the current week runs to the last bar).
  def weekly(closes)
    features = { "rsi14_w" => Indicators.rsi(closes, 14).last }
    if closes.size >= MIN_WEEKLY_MACD
      histogram = Indicators.macd(closes)[:histogram]
      features["macd_hist_w"] = histogram.last
      features["macd_cross_up_w"] = Indicators.crossed_above(histogram)
    end
    features
  end
end
