# Turns plain English into a screen spec (ScreenSpec), deterministically.
#
#   "RSI under 30, price above the 200-day moving average"
#   => conditions [{field: "rsi14", op: "<", value: 30}, {field: "close", op: ">", ref: "sma200"}]
#
# It only *proposes*; Screen#adopt checks the proposal against the contract. A phrase
# the contract has no field for (an EMA, a MACD cross down) is returned as unmapped,
# with the reason, rather than approximated by something close.
module ScreenParser
  # A proposal: conditions and unmapped [{text, reason}], plus the optional parts of a spec.
  Result = Data.define(:conditions, :unmapped, :rank, :universe, :top_n) do
    def initialize(conditions:, unmapped: [], rank: [], universe: {}, top_n: nil) = super
  end
  VERSION = 2 # bump when the rules change, so stored screens say which rules parsed them

  NUM   = /(\d+(?:\.\d+)?)/
  ABOVE = /\b(?:above|over|greater than|more than|higher than|exceeds?|at least)\b|>/
  BELOW = /\b(?:below|under|less than|lower than|within|no more than|at most)\b|</
  FILLER = /\b(?:show|find|give|list|me|all|any|stocks?|names?|tickers?|companies|that|which|whose|are|is|has|have|where|the|on|its|their|a|an|daily|day|chart)\b/
  SMA_PERIODS = [ 20, 50, 200 ].freeze

  # Phrases for whitelisted fields this demo doesn't compute: recognized, so they are
  # refused with the contract's reason (not "no rule matches"), as EquityScout would screen them.
  NOT_COMPUTED = {
    /revenue|sales growth/                                  => "revenue_growth_yoy",
    /profitab|net income|earnings/                          => "net_income_ttm",
    /margin/                                                => "operating_margin",
    /free cash flow|\bfcf\b/                                => "fcf_ttm",
    /market cap|\b(?:large|mid|small|micro)[- ]?caps?\b/    => "market_cap",
    /short interest|days to cover|short squeeze/            => "short_pct_shares_out",
    /\b(?:vs|versus|than|lagging|beating|outperform\w*|underperform\w*)\b.*\b(?:s&p|spy|nasdaq|qqq|index|sector|benchmark)\b/ => "rs_3m_vs_spy"
  }.freeze

  NO_RULE = "no rule matches this"

  # Raised by a rule that recognizes the phrase but has no field for it.
  class Unmappable < StandardError; end

  module_function

  def label = "rules v#{VERSION}"

  def parse(text)
    conditions, unmapped = [], []
    clauses(text).each do |clause|
      found = parse_clause(clause)
      if found.any? then conditions.concat(found)
      elsif clause.gsub(FILLER, "").match?(/[a-z0-9]/) then unmapped << { text: clause, reason: NO_RULE }
      end
    rescue Unmappable => e
      unmapped << { text: clause, reason: e.message }
    end
    Result.new(conditions: conditions, unmapped: unmapped)
  end

  # "a, b and c; d" => ["a", "b", "c", "d"], keeping "between 10 and 20" intact.
  def clauses(text)
    text.downcase
        .gsub(/between\s+\$?#{NUM}\s+and\s+\$?#{NUM}/) { "between #{$1} to #{$2}" }
        .split(/[,;.]\s|[,;]|\band\b|\bwith\b|\bplus\b|\bwhile\b/)
        .map { |c| c.strip.delete_suffix(".") }
        .reject(&:empty?)
  end

  def parse_clause(c)
    found = primary_rule(c)
    found += rsi(c) if c.match?(/oversold|overbought/) && found.none? { |f| f[:field].start_with?("rsi") }
    found
  end

  def primary_rule(c)
    if (field = NOT_COMPUTED.find { |pattern, _| c.match?(pattern) }&.last)
      raise Unmappable, "#{ScreenSpec.label(field)} #{ScreenSpec.unavailable_reason(field)}"
    end

    case c
    when /\brsi\b/                                  then rsi(c)
    when /\bmacd\b/                                 then macd(c)
    when /golden cross|50[- ]day (?:average |ma |sma )?(?:is )?above (?:the )?200/ then golden_cross(c)
    when /\bvolume\b/                               then volume(c)
    when /52[- ]?w(?:ee)?k|year(?:ly)? high/        then drawdown(c)
    when /\b(?:sma|ema|moving average|ma|average)\b/ then moving_average(c)
    when /\b\d+[- ]?months?\b|\breturn\b/           then momentum(c)
    when /\bprice\b|\bclose[sd]?\b|\btrading\b|\$/  then price(c)
    else []
    end
  end

  def weekly?(c) = c.match?(/\bweekly\b|\bweek\b/)

  def rsi(c)
    period = c[/rsi\s*\(?\s*(\d+)/, 1]&.to_i || 14
    raise Unmappable, "only RSI(14) is computed (daily rsi14 and weekly rsi14_w), not RSI(#{period})" unless period == 14

    op, value = comparison(c) if c.match?(/\brsi\b/)
    op, value = "<", 30 if !op && c.include?("oversold")
    op, value = ">", 70 if !op && c.include?("overbought")
    return [] unless op
    [ { field: weekly?(c) ? "rsi14_w" : "rsi14", op: op, value: value } ]
  end

  def macd(c)
    if c.match?(/\b(?:down|bearish|negative)\b|cross(?:es|ed|ing)? (?:below|under)/)
      raise Unmappable, "there is no field for a MACD cross down (macd_hist < 0 means MACD is below its signal)"
    end
    if c.match?(/cross|bullish/)
      [ { field: weekly?(c) ? "macd_cross_up_w" : "macd_cross_up", op: "==", value: true } ]
    elsif c.match?(/above|over|positive/)
      [ { field: weekly?(c) ? "macd_hist_w" : "macd_hist", op: ">", value: 0 } ]
    else []
    end
  end

  def golden_cross(_c) = [ { field: "sma50_above_sma200", op: "==", value: true } ]

  def volume(c)
    period = c[/(\d+)[- ]?(?:day|d|bar|session)\b/, 1]&.to_i || 20
    raise Unmappable, "volume is compared with its 20- or 50-day average only, not #{period} days" unless period.in?([ 20, 50 ])

    multiplier = c[/#{NUM}\s*(?:x|×|times)\b/, 1]&.to_f || 1
    [ { field: "volume_ratio_#{period}d", op: c.match?(BELOW) ? "<" : ">", value: number(multiplier) } ]
  end

  # drawdown_52w is close / 52-week high - 1: "within 5%" is >= -0.05, "down at least 20%" is <= -0.20.
  def drawdown(c)
    pct = c[/#{NUM}\s*(?:%|percent|pct)/, 1]&.to_f
    near = c.match?(/\b(?:near|close to|at)\b/)
    pct ||= 5.0 if near
    return [] unless pct
    within = c.match?(/\b(?:within|less than|under|no more than|at most|near|close to)\b/)
    [ { field: "drawdown_52w", op: within ? ">=" : "<=", value: number(-pct / 100) } ]
  end

  def moving_average(c)
    raise Unmappable, "there is no EMA field; only the 20-, 50- and 200-day simple averages are computed" if c.match?(/\bema\b|exponential/)
    raise Unmappable, "moving averages are daily only (20-, 50- and 200-day)" if weekly?(c)

    period = (c[/(\d+)[- ]?(?:day|d|bar)?\s*(?:simple )?(?:sma|moving average|ma|average)\b/, 1] || c[/\bsma\s*\(?\s*(\d+)/, 1])&.to_i || 50
    raise Unmappable, "only the 20-, 50- and 200-day averages are computed, not #{period} days" unless period.in?(SMA_PERIODS)

    [ { field: "close", op: c.match?(BELOW) ? "<" : ">", ref: "sma#{period}" } ]
  end

  # "up over the last 3 months" -> mom_3m > 0; "6-month return above 10%" -> mom_6m > 0.10.
  def momentum(c)
    months = c[/(\d+)[- ]?months?/, 1]&.to_i || (c.match?(/\byear\b|12[- ]?month/) ? 12 : nil)
    return [] unless months
    raise Unmappable, "returns are computed over 1, 3, 6 and 12 months, not #{months}" unless ScreenSpec::MONTH_DAYS.key?(months)

    op, pct = comparison(c, percent: true)
    op ||= c.match?(/\bdown\b|\bfell\b|\blost\b/) ? "<" : (c.match?(/\bup\b|\brose\b|\bgained\b/) ? ">" : nil)
    return [] unless op
    [ { field: "mom_#{months}m", op: op, value: number((pct || 0) / 100.0) } ]
  end

  def price(c)
    if (m = c.match(/between\s+#{NUM}\s+to\s+#{NUM}/))
      return [ { field: "close", op: "between", value: [ m[1].to_f, m[2].to_f ].sort.map { number(_1) } } ]
    end
    op, value = comparison(c)
    op ? [ { field: "close", op: op, value: value } ] : []
  end

  # Finds "<above|below> [$]N[%]" in a clause.
  def comparison(c, percent: false)
    if (m = c.match(/(#{ABOVE}|#{BELOW})\s*\$?\s*#{NUM}(\s*%)?/))
      return if percent && !m[3] && !m[1].match?(/</)
      [ m[1].match?(ABOVE) ? ">" : "<", number(m[2].to_f) ]
    end
  end

  def number(x) = x == x.to_i ? x.to_i : x.round(6)
end
