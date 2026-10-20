# The screen spec: the typed, whitelisted contract between whoever proposes a screen
# (the rule-based parser or an LLM) and the code that runs it. It is the same contract
# as EquityScout's, the Python version of this product (src/scout/spec.py there): same
# field names, units, operators, validation messages and plain-English wording, so a
# spec means the same thing in both.
#
# All ratios are decimals: 0.10 means 10%. Money is in US dollars.
#
# Every field stays in the whitelist, but this demo only computes the ones it can from
# daily prices (AVAILABLE). A condition on any other field (revenue growth, market cap,
# short interest...) is refused with the reason, and shown as "not screened".
module ScreenSpec
  VERSION = 1

  Field = Data.define(:name, :group, :kind, :desc)

  MONTH_DAYS = { 1 => 21, 3 => 63, 6 => 126, 12 => 252 }.freeze

  BENCHMARKS = {
    "spy" => "the S&P 500 (SPY)", "qqq" => "the Nasdaq-100 (QQQ)", "iwm" => "the Russell 2000 (IWM)",
    "smh" => "the chip index (SMH)", "soxx" => "the chip index (SOXX)", "xlk" => "tech stocks (XLK)",
    "xlf" => "financials (XLF)", "xle" => "energy stocks (XLE)", "xlv" => "health care (XLV)",
    "xli" => "industrials (XLI)", "xlu" => "utilities (XLU)", "xly" => "consumer discretionary (XLY)",
    "xlp" => "consumer staples (XLP)", "xlb" => "materials (XLB)", "xlre" => "real estate (XLRE)",
    "xlc" => "communication services (XLC)"
  }.freeze

  FIELDS = [
    [ "market_cap", "size", "usd", "price x latest shares outstanding (SEC cover page), as of the run date" ],
    [ "ev", "size", "usd", "enterprise value = market cap + total debt - cash and short-term investments" ],
    [ "close", "technical", "usd", "last adjusted close" ],
    [ "avg_dollar_volume_50d", "size", "usd", "mean of close x volume over the last 50 sessions" ],
    [ "sma20", "technical", "usd", "20-day simple moving average of close" ],
    [ "sma50", "technical", "usd", "50-day simple moving average of close" ],
    [ "sma200", "technical", "usd", "200-day simple moving average of close" ],
    [ "pct_vs_sma20", "technical", "ratio", "close / SMA20 - 1" ],
    [ "pct_vs_sma50", "technical", "ratio", "close / SMA50 - 1" ],
    [ "pct_vs_sma200", "technical", "ratio", "close / SMA200 - 1" ],
    [ "sma50_above_sma200", "technical", "bool", "true when SMA50 > SMA200 (golden-cross structure)" ],
    [ "rsi14", "technical", "number", "Wilder RSI(14), 0-100" ],
    [ "macd", "technical", "number", "MACD line, EMA12 - EMA26 of close" ],
    [ "macd_signal", "technical", "number", "EMA9 of the MACD line" ],
    [ "macd_hist", "technical", "number", "MACD - signal; > 0 means MACD above its signal" ],
    [ "volume_ratio_50d", "technical", "number", "today's volume / mean volume of the prior 50 sessions" ],
    [ "drawdown_52w", "technical", "ratio", "close / 52-week (252-session) high close - 1; -0.20 = 20% below the high" ],
    [ "volume_ratio_20d", "technical", "number", "today's volume / mean volume of the prior 20 sessions" ],
    [ "macd_cross_up", "technical", "bool",
      "true when the daily MACD crossed above its signal on the last session (hist <= 0 the day before, > 0 now)" ],
    [ "rsi14_w", "technical", "number", "Wilder RSI(14) of weekly closes (weeks end Friday), 0-100" ],
    [ "macd_hist_w", "technical", "number", "weekly MACD minus its signal, MACD(12, 26, 9) of weekly closes" ],
    [ "macd_cross_up_w", "technical", "bool",
      "true when the weekly MACD crossed above its signal in the latest week (hist <= 0 the week before, > 0 now)" ],
    *MONTH_DAYS.map { |m, days| [ "mom_#{m}m", "technical", "ratio", "#{m}-month price return (#{days} sessions)" ] },
    *MONTH_DAYS.keys.product(BENCHMARKS.keys).map do |m, b|
      [ "rs_#{m}m_vs_#{b}", "technical", "ratio", "#{m}-month return minus #{b.upcase} #{m}-month return (negative = lagging)" ]
    end,
    [ "revenue_ttm", "fundamental", "usd", "trailing-twelve-month revenue (sum of last 4 fiscal quarters)" ],
    [ "revenue_growth_yoy", "fundamental", "ratio", "TTM revenue vs TTM revenue one year earlier - 1" ],
    [ "revenue_growth_q_yoy", "fundamental", "ratio", "latest fiscal quarter revenue vs same quarter a year earlier - 1" ],
    [ "revenue_growth_accel", "fundamental", "ratio",
      "latest quarter YoY growth minus prior quarter YoY growth; > 0 means growth is accelerating" ],
    [ "gross_margin", "fundamental", "ratio", "TTM gross profit / TTM revenue" ],
    [ "operating_margin", "fundamental", "ratio", "TTM operating income / TTM revenue" ],
    [ "net_margin", "fundamental", "ratio", "TTM net income / TTM revenue" ],
    [ "net_income_ttm", "fundamental", "usd", "TTM net income; > 0 means profitable on a GAAP basis" ],
    [ "fcf_ttm", "fundamental", "usd", "TTM free cash flow = operating cash flow - capital expenditure" ],
    [ "fcf_margin", "fundamental", "ratio", "TTM FCF / TTM revenue" ],
    [ "fcf_yield", "fundamental", "ratio", "TTM FCF / market cap" ],
    [ "net_debt", "fundamental", "usd", "total debt - cash and short-term investments (negative = net cash)" ],
    [ "ev_to_sales", "fundamental", "number", "EV / TTM revenue" ],
    [ "short_pct_shares_out", "short_interest", "ratio",
      "FINRA short interest / shares outstanding (not float: float is not in free data)" ],
    [ "days_to_cover", "short_interest", "days", "FINRA days to cover (short shares / average daily volume)" ]
  ].to_h { |name, group, kind, desc| [ name, Field.new(name, group, kind, desc) ] }.freeze

  # What this demo computes from daily prices (Features.for); everything else is refused.
  AVAILABLE = (%w[close avg_dollar_volume_50d sma20 sma50 sma200 pct_vs_sma20 pct_vs_sma50 pct_vs_sma200
                  sma50_above_sma200 rsi14 macd macd_signal macd_hist volume_ratio_50d drawdown_52w volume_ratio_20d
                  macd_cross_up rsi14_w macd_hist_w macd_cross_up_w] + MONTH_DAYS.keys.map { |m| "mom_#{m}m" }).freeze

  OPS = %w[< <= > >= between ==].freeze
  UNIVERSE_KEYS = %w[market_cap_min market_cap_max min_price min_avg_dollar_volume sectors industry_groups
                     industries exclude_industries themes].freeze
  # The universe here is the fixed list in db/universe.txt; only filters on computed fields apply.
  UNIVERSE_FILTERS = { "min_price" => "close", "min_avg_dollar_volume" => "avg_dollar_volume_50d" }.freeze
  MAX_TOP_N = 10
  DEFAULT_TOP_N = 5

  LABELS = {
    "market_cap" => "Market cap", "ev" => "Enterprise value", "close" => "Price",
    "avg_dollar_volume_50d" => "Avg daily $ volume (50 days)", "sma20" => "20-day average", "sma50" => "50-day average",
    "sma200" => "200-day average", "pct_vs_sma20" => "Price vs 20-day average", "pct_vs_sma50" => "Price vs 50-day average",
    "pct_vs_sma200" => "Price vs 200-day average", "sma50_above_sma200" => "50-day above 200-day average",
    "rsi14" => "RSI (14-day)", "macd" => "MACD", "macd_signal" => "MACD signal", "macd_hist" => "MACD minus signal",
    "volume_ratio_50d" => "Volume vs 50-day average", "drawdown_52w" => "From 52-week high",
    "volume_ratio_20d" => "Volume vs 20-day average", "macd_cross_up" => "MACD crossed above signal (daily)",
    "rsi14_w" => "RSI (14-week)", "macd_hist_w" => "Weekly MACD minus signal",
    "macd_cross_up_w" => "MACD crossed above signal (weekly)",
    "revenue_ttm" => "Revenue, last 12 months", "revenue_growth_yoy" => "Revenue growth (year over year)",
    "revenue_growth_q_yoy" => "Revenue growth, latest quarter (year over year)",
    "revenue_growth_accel" => "Revenue growth acceleration", "gross_margin" => "Gross margin",
    "operating_margin" => "Operating margin", "net_margin" => "Net margin", "net_income_ttm" => "Net income, last 12 months",
    "fcf_ttm" => "Free cash flow, last 12 months", "fcf_margin" => "Free cash flow margin",
    "fcf_yield" => "Free cash flow yield", "net_debt" => "Net debt", "ev_to_sales" => "EV / sales",
    "short_pct_shares_out" => "Short interest (% of shares)", "days_to_cover" => "Days to cover (short interest)",
    **MONTH_DAYS.keys.to_h { |m| [ "mom_#{m}m", "#{m}-month return" ] },
    **MONTH_DAYS.keys.product(BENCHMARKS.to_a).to_h { |m, (b, name)| [ "rs_#{m}m_vs_#{b}", "#{m}-month return vs #{name}" ] }
  }.freeze

  module_function

  def label(field) = LABELS.fetch(field, field)
  def kind(field) = FIELDS[field]&.kind || "number"

  # Why a whitelisted field can't be screened here, or nil if it can.
  def unavailable_reason(field)
    return if AVAILABLE.include?(field)

    case FIELDS[field]&.group
    when "fundamental"    then "needs financial statements (SEC filings), which this demo doesn't load"
    when "short_interest" then "needs FINRA short interest, which this demo doesn't load"
    when "size"           then "needs shares outstanding and balance-sheet data (SEC filings), which this demo doesn't load"
    else                       "needs benchmark ETF prices, which this demo doesn't load"
    end
  end

  # Every problem with one condition, worded as in EquityScout's validate(); [] when valid.
  def condition_problems(c, where: "condition")
    return [ "#{where} must be an object" ] unless c.is_a?(Hash)

    c = c.stringify_keys
    problems = (c.keys - %w[field op value ref why]).map { |k| "#{where}: unknown key '#{k}' (allowed: field, op, ref, value, why)" }
    field, op = c["field"], c["op"]
    return problems << "#{where}: unknown field #{field.inspect}; it is not in the whitelist of computed fields" unless FIELDS.key?(field)
    return problems << "#{where}: operator #{op.inspect} not allowed (allowed: #{OPS.sort.join(", ")})" unless OPS.include?(op)
    if c.key?("value") == c.key?("ref")
      return problems << "#{where}: give exactly one of 'value' (a threshold) or 'ref' (another field)"
    end

    if kind(field) == "bool"
      problems << "#{where}: '#{field}' is boolean; use op '==' with value true/false" unless op == "==" && c["value"].in?([ true, false ])
      return problems
    end
    return problems << "#{where}: '==' is only for boolean fields" if op == "=="

    if c.key?("ref")
      ref = c["ref"]
      if !FIELDS.key?(ref) then problems << "#{where}: unknown ref field #{ref.inspect}"
      elsif kind(ref) != kind(field) then problems << "#{where}: cannot compare '#{field}' (#{kind(field)}) with '#{ref}' (#{kind(ref)})"
      elsif op == "between" then problems << "#{where}: 'between' needs a [low, high] value, not a ref"
      end
      return problems
    end

    value = c["value"]
    values =
      if op == "between"
        unless value.is_a?(Array) && value.size == 2 && value.all? { number?(_1) } && value[0] < value[1]
          return problems << "#{where}: 'between' needs value [low, high] with low < high"
        end
        value
      else
        return problems << "#{where}: value must be a number, got #{value.inspect}" unless number?(value)
        [ value ]
      end
    values.each do |x|
      problems << "#{where}: #{field} is a decimal ratio (0.10 = 10%); #{x} looks like a percent" if kind(field) == "ratio" && x.abs > 20
      problems << "#{where}: #{field} thresholds must be within 0-100" if field.in?(%w[rsi14 rsi14_w]) && !(0..100).cover?(x)
    end
    problems
  end

  # Problems with one rank entry ({field, direction, weight}); [] when valid.
  def rank_problems(r, where: "rank")
    return [ "#{where} must be an object" ] unless r.is_a?(Hash)

    r = r.stringify_keys
    problems = (r.keys - %w[field direction weight]).map { |k| "#{where}: unknown key '#{k}'" }
    if !FIELDS.key?(r["field"]) || kind(r["field"]) == "bool"
      problems << "#{where}: field #{r["field"].inspect} is not a rankable whitelisted field"
    end
    problems << "#{where}: direction must be 'asc' or 'desc'" unless r["direction"].in?(%w[asc desc])
    problems << "#{where}: weight must be a positive number" unless number?(r.fetch("weight", 1)) && r.fetch("weight", 1).positive?
    problems
  end

  def number?(x) = x.is_a?(Numeric) && x.to_f.finite?

  # Problems with the universe; [] when valid. Only filters on computed fields
  # (UNIVERSE_FILTERS) can run here; the rest come back from unsupported_universe.
  def universe_problems(universe)
    return [ "'universe' must be an object" ] unless universe.is_a?(Hash)

    universe.stringify_keys.flat_map do |key, value|
      if !UNIVERSE_KEYS.include?(key) then [ "unknown universe key '#{key}' (allowed: #{UNIVERSE_KEYS.sort.join(", ")})" ]
      elsif UNIVERSE_FILTERS.key?(key) && !(number?(value) && value >= 0) then [ "universe.#{key} must be a non-negative number, got #{value.inspect}" ]
      else []
      end
    end
  end

  # ---- running a spec (EquityScout's src/scout/screen.py) ----

  # :pass, :fail or :missing (a value this symbol doesn't have: reported as a gap, never imputed).
  def check(c, features)
    c = c.stringify_keys
    x = features[c["field"]]
    y = c["ref"] ? features[c["ref"]] : c["value"]
    return :missing if x.nil? || y.nil?

    passed =
      case c["op"]
      when "==" then x == y
      when "between" then x.between?(*y)
      else x.public_send(c["op"], y)
      end
    passed ? :pass : :fail
  end

  # The universe filters this demo can run, as conditions: min_price -> close >= value.
  def universe_conditions(universe)
    universe.stringify_keys.slice(*UNIVERSE_FILTERS.keys).map { |key, value| { "field" => UNIVERSE_FILTERS[key], "op" => ">=", "value" => value } }
  end

  # When no ranking is given: rank by each threshold condition's field, in the direction
  # of its threshold ("rsi14 < 30": lowest first); "close > sma200" ranks by distance above
  # the average. With nothing to rank by, the most liquid names come first.
  def default_rank(conditions)
    rank = conditions.map(&:stringify_keys).filter_map do |c|
      direction = c["op"].to_s.start_with?(">") ? "desc" : "asc"
      if c["ref"]&.match?(/\Asma\d+\z/) && c["field"] == "close" then { "field" => "pct_vs_#{c["ref"]}", "direction" => direction, "weight" => 1 }
      elsif !c["ref"] && number?(c["value"]) && c["op"].in?(%w[< <= > >=]) then { "field" => c["field"], "direction" => direction, "weight" => 1 }
      end
    end
    rank.uniq { _1["field"] }.presence || [ { "field" => "avg_dollar_volume_50d", "direction" => "desc", "weight" => 1 } ]
  end

  # Composite score = weighted mean of percentile ranks (0-1, higher is better), pandas'
  # rank(pct=True, method="average"): a name missing a ranking field gets 0 for it.
  # rows: [[key, features], ...]; returns { key => score }.
  def scores(rows, rank)
    total = rank.sum { _1["weight"] }
    rows.to_h do |key, features|
      [ key, rank.sum { |r| r["weight"] * percentile(rows, r, features[r["field"]]) } / total ]
    end
  end

  def percentile(rows, r, x)
    return 0.0 if x.nil?

    values = rows.filter_map { |_, features| features[r["field"]] }
    below, ties = values.count { r["direction"] == "desc" ? _1 < x : _1 > x }, values.count(x)
    (below + (ties + 1) / 2.0) / values.size
  end

  # ---- plain English (EquityScout's docs/ui.js plainCond / plainVal) ----

  OPW = { ">" => "above", ">=" => "at least", "<" => "below", "<=" => "at most" }.freeze
  SYMBOLS = { ">" => ">", ">=" => "≥", "<" => "<", "<=" => "≤" }.freeze

  def describe(c)
    c = c.stringify_keys
    f, v, op = c["field"], c["value"], c["op"]
    if c["ref"]
      if f == "close" && (sma = c["ref"][/\Asma(\d+)\z/, 1])
        return "Price #{op.start_with?(">") ? "above" : "below"} its #{sma}-day average"
      end
      return "#{label(f)} #{OPW.fetch(op, op)} #{label(c["ref"]).downcase}"
    end
    if f == "sma50_above_sma200"
      return v ? "50-day average above 200-day average (uptrend)" : "50-day average below 200-day average (downtrend)"
    end
    return "#{label(f)} between #{plain_value(f, v[0])} and #{plain_value(f, v[1])}" if op == "between"

    if f == "drawdown_52w" && v.is_a?(Numeric) && v.negative?
      return "Down at least #{trim(-v * 100)}% from 52-week high" if op.in?(%w[<= <])
      return "Within #{trim(-v * 100)}% of 52-week high" if op.in?(%w[>= >])
    end
    if (sma = f[/\Apct_vs_sma(\d+)\z/, 1]) && v.is_a?(Numeric)
      return "Price #{op.start_with?(">") ? "above" : "below"} its #{sma}-day average" if v.zero?
      if op.start_with?("<") == v.negative?
        return "Price at least #{trim(v.abs * 100)}% #{v.positive? ? "above" : "below"} its #{sma}-day average"
      end
    end
    if (m = f.match(/\Ars_(\d+)m_vs_(\w+)\z/)) && v == 0
      return "#{op.start_with?("<") ? "Lagging" : "Beating"} #{BENCHMARKS.fetch(m[2], m[2].upcase)} over #{months(m[1])}"
    end
    if (m = f[/\Amom_(\d+)m\z/, 1]) && v == 0
      return "Price #{op.start_with?(">") ? "up" : "down"} over #{months(m)}"
    end
    return "Volume at least #{trim(v)}× its 50-day average" if f == "volume_ratio_50d" && op.start_with?(">")
    if f == "volume_ratio_20d" && op.start_with?(">")
      return v == 1 ? "Volume above its 20-day average" : "Volume at least #{trim(v)}× its 20-day average"
    end
    if f == "macd_cross_up_w"
      return v ? "Weekly MACD crossed above its signal this week" : "Weekly MACD did not cross above its signal this week"
    end
    if f == "macd_cross_up"
      return v ? "Daily MACD crossed above its signal on the last session" : "Daily MACD did not cross above its signal on the last session"
    end
    return "Daily RSI (14) under #{trim(v)}" if f == "rsi14" && op.start_with?("<")
    return "Weekly RSI (14) under #{trim(v)}" if f == "rsi14_w" && op.start_with?("<")

    "#{label(f)} #{SYMBOLS.fetch(op, op)} #{plain_value(f, v)}"
  end

  def plain_value(field, v)
    return v ? "yes" : "no" if v.in?([ true, false ])
    return v.to_s unless v.is_a?(Numeric)

    case kind(field)
    when "ratio" then "#{trim(v * 100)}%"
    when "usd"   then money(v)
    when "days"  then "#{trim(v)} days"
    else              trim(v)
    end
  end

  def money(v)
    sign, a = (v.negative? ? "-" : ""), v.abs
    return "#{sign}$#{trim(a / 1e12)}T" if a >= 1e12
    return "#{sign}$#{trim(a / 1e9)}B" if a >= 1e9
    return "#{sign}$#{trim(a / 1e6)}M" if a >= 1e6

    "#{sign}$#{trim(a)}"
  end

  # JavaScript's String(Number(x.toFixed(2))): at most two decimals, no trailing zeros.
  def trim(x) = x.to_f.round(2).then { |r| r == r.to_i ? r.to_i.to_s : r.to_s }

  def months(m) = m == "1" ? "1 month" : "#{m} months"
end
