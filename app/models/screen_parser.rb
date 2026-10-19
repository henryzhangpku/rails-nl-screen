# Turns plain English into condition attributes, deterministically.
#
#   ScreenParser.parse("RSI(14) under 30, price above the 200-day moving average")
#   # => #<data Result conditions=[{indicator: "rsi", operator: "below", ...}, ...], unrecognized=[]>
#
# It only *proposes* attributes; Condition validations decide what is allowed.
module ScreenParser
  Result = Data.define(:conditions, :unrecognized)
  VERSION = 1 # bump when the rules change, so stored screens say which rules parsed them

  NUM   = /(\d+(?:\.\d+)?)/
  ABOVE = /\b(?:above|over|greater than|more than|higher than|exceeds?|at least)\b|>/
  BELOW = /\b(?:below|under|less than|lower than|within|no more than|at most)\b|</
  FILLER = /\b(?:show|find|give|list|me|all|any|stocks?|names?|tickers?|companies|that|which|whose|are|is|has|have|where|the|on|its|their|a|an|daily|day|chart)\b/

  module_function

  def label = "rules v#{VERSION}"

  def parse(text)
    conditions = []
    unrecognized = []

    clauses(text).each do |clause|
      found = parse_clause(clause)
      if found.any?
        timeframe = clause.match?(/\bweekly\b/) ? "weekly" : "daily"
        conditions.concat(found.map { |c| c.merge(timeframe: timeframe) })
      elsif clause.gsub(FILLER, "").match?(/[a-z0-9]/)
        unrecognized << clause
      end
    end

    Result.new(conditions, unrecognized)
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
    found += rsi(c) if c.match?(/oversold|overbought/) && found.none? { |f| f[:indicator] == "rsi" }
    found
  end

  def primary_rule(c)
    case c
    when /\brsi\b/                          then rsi(c)
    when /\bmacd\b/                         then macd(c)
    when /\bvolume\b/                       then volume(c)
    when /52[- ]?w(?:ee)?k|year(?:ly)? high/ then drawdown(c)
    when /\b(?:sma|ema|moving average|ma)\b/ then moving_average(c)
    when /\bprice\b|\bclose[sd]?\b|\btrading\b|\$/ then price(c)
    else []
    end
  end

  def rsi(c)
    period = c[/rsi\s*\(?\s*(\d+)/, 1]&.to_i
    op, value = comparison(c) if c.match?(/\brsi\b/)
    op, value = "below", 30.0 if !op && c.include?("oversold")
    op, value = "above", 70.0 if !op && c.include?("overbought")
    return [] unless op
    [ { indicator: "rsi", period: period, operator: op, value: value } ]
  end

  def macd(c)
    down = c.match?(/\b(?:down|below|bearish|negative|under)\b/)
    [ { indicator: "macd", operator: down ? "crosses_down" : "crosses_up" } ]
  end

  def volume(c)
    period = c[/(\d+)[- ]?(?:day|d|bar|session)\b/, 1]&.to_i
    multiplier = c[/#{NUM}\s*(?:x|times)\b/, 1]&.to_f
    op = c.match?(BELOW) ? "below" : "above"
    [ { indicator: "volume", period: period, operator: op, value: multiplier } ]
  end

  def drawdown(c)
    pct = c[/#{NUM}\s*(?:%|percent|pct)/, 1]&.to_f
    near = c.match?(/\b(?:near|close to|at)\b/)
    op = c.match?(/\b(?:within|less than|under|no more than|at most|near|close to)\b/) ? "below" : "above"
    pct ||= 5.0 if near
    return [] unless pct
    [ { indicator: "drawdown", operator: op, value: pct } ]
  end

  def moving_average(c)
    period = c[/(\d+)[- ]?(?:day|d|bar|week|wk)?\s*(?:simple |exponential )?(?:sma|ema|moving average|ma)\b/, 1] ||
             c[/\b(?:sma|ema)\s*\(?\s*(\d+)/, 1]
    indicator = c.match?(/\bema\b|exponential/) ? "ema" : "sma"
    op = c.match?(BELOW) ? "below" : "above"
    [ { indicator: indicator, period: period&.to_i, operator: op } ]
  end

  def price(c)
    if (m = c.match(/between\s+#{NUM}\s+to\s+#{NUM}/))
      low, high = [ m[1].to_f, m[2].to_f ].sort
      return [ { indicator: "price", operator: "above", value: low }, { indicator: "price", operator: "below", value: high } ]
    end
    op, value = comparison(c)
    op ? [ { indicator: "price", operator: op, value: value } ] : []
  end

  # Finds "<above|below> [$]N" in a clause.
  def comparison(c)
    if (m = c.match(/(#{ABOVE}|#{BELOW})\s*\$?\s*#{NUM}/))
      [ m[1].match?(ABOVE) ? "above" : "below", m[2].to_f ]
    end
  end
end
