# A plain-English query, the screen spec understood from it (the contract shared with
# EquityScout, see ScreenSpec), and its conditions. Running a screen walks every symbol
# through the funnel, records a Match per survivor, then ranks them.
# == Schema Information
#
# Table name: screens
# Database name: primary
#
#  id            :integer          not null, primary key
#  error_message :string
#  funnel        :json             not null
#  matches_count :integer          default(0), not null
#  notes         :json             not null
#  parser        :string
#  proposal      :json             not null
#  query         :text             not null
#  scanned_count :integer          default(0), not null
#  source        :string           default("rules"), not null
#  spec          :json             not null
#  status        :string           default("pending"), not null
#  universe_size :integer          default(0), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class Screen < ApplicationRecord
  has_many :conditions, -> { order(:position) }, dependent: :destroy
  # Ranked once the run finishes; until then in the order found.
  has_many :matches, -> { order(Match.arel_table[:rank].asc.nulls_last, :id) }, dependent: :destroy

  enum :status, %w[pending running done failed].index_by(&:itself)
  SOURCES = %w[rules llm].freeze

  # History filters. Each scope ignores a blank argument, so the controller can chain them.
  scope :matching, ->(text) { where("query LIKE ?", "%#{sanitize_sql_like(text)}%") if text.present? }
  scope :with_status, ->(status) { where(status: status) if status.in?(statuses.keys) }
  scope :from_source, ->(source) { where(source: source) if source.in?(SOURCES) }
  scope :with_matches, ->(flag = true) { where(matches_count: 1..) if flag.present? }

  validates :query, presence: true
  validate :understood_something

  # On every change (status, progress) tell open pages to refresh themselves.
  # Turbo 8 re-fetches the page and morphs in the difference, so the result is
  # always the latest state, even if two broadcasts arrive out of order.
  after_update_commit -> { broadcast_refresh_to self }

  NO_DATA = "No data for " # the note Screen#run leaves about skipped symbols
  MAX_CONDITIONS = 10 # each one is evaluated against every symbol in the universe

  # Shown as "Try:" buttons on the form, and used to build the static demo. The last one
  # is EquityScout's daily-and-weekly example, word for word: on most days it finds no
  # names, and both versions of the product say so rather than loosening it quietly.
  EXAMPLES = [
    "RSI under 40, price above the 200-day moving average",
    "within 5% of the 52-week high, price above the 50-day average, volume above its 20-day average",
    "golden cross, up over the last 3 months, weekly RSI above 60",
    "down at least 20% from the 52-week high, RSI under 40, price between $20 and $200",
    "MACD above its signal, volume above its 20-day average, price above the 50-day average",
    "RSI under 30 on the daily, MACD crossing above its signal on the weekly, volume above its 20-day average"
  ].freeze

  # Parse `query` into an unsaved Screen. An LLM proposes when configured;
  # otherwise (or if it fails) the rule-based parser does. Either way the proposal
  # only becomes conditions after it passes the contract (ScreenSpec).
  def self.from_query(query, parser: ScreenParser::LLM.enabled? ? ScreenParser::LLM : ScreenParser)
    screen = new(query: query.to_s.strip)
    screen.adopt(screen.propose_with(parser))
    screen
  end

  # What the LLM can fail with: the provider's API errors, the network, or a reply we
  # can't use. Anything else is a bug, and raises.
  LLM_ERRORS = [ RubyLLM::Error, Faraday::Error, JSON::ParserError, ScreenParser::LLM::Error ].freeze

  def propose_with(parser)
    self.source = parser == ScreenParser ? "rules" : "llm"
    record_proposal(parser, parser.parse(query))
  rescue *LLM_ERRORS => e
    Rails.logger.warn("#{parser} failed: #{e.class}: #{e.message}")
    notes << "The LLM was unavailable (#{e.class.name.demodulize}), so the rule-based parser was used"
    self.source = "rules"
    record_proposal(ScreenParser, ScreenParser.parse(query))
  end

  # Keep exactly what was proposed (and by which parser/prompt version) next to
  # what code accepted, so every screen can be audited later.
  def record_proposal(parser, result)
    self.parser = parser.label
    self.proposal = result.to_h.as_json
    result
  end

  # Checks a proposal against the contract. Valid conditions on fields this demo computes
  # become Conditions; everything else is "not screened", with the reason (never dropped
  # silently, never approximated). The accepted spec is stored as `spec`.
  def adopt(proposal)
    unmapped = Array(proposal.unmapped).filter_map do |u|
      u = u.to_h.stringify_keys if u.respond_to?(:to_h)
      { "text" => u["text"].to_s, "reason" => u["reason"].to_s } if u.is_a?(Hash) && u["text"].present?
    end
    accepted = []
    Array(proposal.conditions).each_with_index do |c, i|
      c = c.to_h.stringify_keys.slice("field", "op", "value", "ref", "why") if c.respond_to?(:to_h)
      if (problems = ScreenSpec.condition_problems(c, where: "conditions[#{i}]")).any?
        unmapped << { "text" => c.to_json, "reason" => problems.join("; ") }
      elsif (unavailable = [ c["field"], c["ref"] ].compact.find { ScreenSpec.unavailable_reason(_1) })
        unmapped << { "text" => ScreenSpec.describe(c), "reason" => "#{ScreenSpec.label(unavailable)} #{ScreenSpec.unavailable_reason(unavailable)}" }
      elsif accepted.size == MAX_CONDITIONS
        notes << "Kept the first #{MAX_CONDITIONS} conditions"
        break
      else
        accepted << c
        conditions.build(c.slice("field", "op", "value", "ref").merge("position" => conditions.size))
      end
    end
    self.spec = {
      "version" => ScreenSpec::VERSION, "observation" => query, "universe" => adopt_universe(proposal.universe, unmapped),
      "conditions" => accepted, "rank" => adopt_rank(proposal.rank, accepted), "top_n" => adopt_top_n(proposal.top_n),
      "unmapped" => unmapped, "notes" => ""
    }
  end

  # The parts of the query this screen does not test, with the reason for each.
  def not_screened = spec.fetch("unmapped", [])

  def top_n = spec.fetch("top_n", ScreenSpec::DEFAULT_TOP_N)

  # Results table columns, as EquityScout's: the fields the conditions and the ranking read.
  def table_fields
    (conditions.flat_map { [ _1.field, _1.ref ] } + spec.fetch("rank", []).pluck("field")).compact.uniq
  end

  # The steps of the funnel, in order: the universe, its filters, then each condition.
  def steps
    universe = ScreenSpec.universe_conditions(spec.fetch("universe", {})).map { [ ScreenSpec.describe(_1), _1 ] }
    universe + conditions.map { [ _1.label, _1.to_spec ] }
  end

  # Called from RunScreenJob. Walks every symbol through the funnel, streaming matches
  # as they're found, then ranks them. A repeated or retried run starts over, so each
  # symbol matches at most once (and the unique index on matches [screen_id, symbol] holds).
  def run(symbols = Universe.symbols, source: MarketData.source)
    # One DELETE, without loading the association (so `matches` still reads ranked).
    # It skips the counter cache, which can only be written in SQL, so recount.
    Match.where(screen: self).delete_all
    matches.reset # forget any matches loaded from an earlier run
    self.class.reset_counters(id, :matches)
    notes.reject! { |note| note.start_with?(NO_DATA) }
    @counts = Array.new(steps.size) { Hash.new(0) }
    @with_data = 0
    update!(status: :running, universe_size: symbols.size, scanned_count: 0, funnel: [])
    skipped = []
    last_saved = Time.current
    symbols.each do |symbol|
      scan(symbol, source: source)
    rescue MarketData::Error => e
      Rails.logger.warn("Skipping #{symbol}: #{e.message}")
      skipped << symbol
    ensure
      self.scanned_count += 1
      # Save progress at most twice a second: each save broadcasts a page refresh.
      if Time.current - last_saved > 0.5
        self.funnel = funnel_rows
        save!
        last_saved = Time.current
      end
    end
    # Nothing at all usually means the price source is down: fail, so the job retries.
    raise MarketData::Error, "No data for any of the #{symbols.size} symbols" if symbols.any? && skipped.size == symbols.size

    notes << "#{NO_DATA}#{skipped.size} symbol(s): #{skipped.join(", ")}" if skipped.any?
    rank_matches
    matches.reset # re-read in rank order
    # The counter cache is kept in SQL (and is read-only here), so refresh the in-memory value.
    self.matches_count = matches.count
    update!(status: :done, funnel: funnel_rows)
  rescue => e
    update!(status: :failed, error_message: e.message)
    raise
  end

  # One symbol through the funnel: it stops at the first step it fails, or lacks data for.
  def scan(symbol, source: MarketData.source)
    daily = Bar.series_for(symbol, source: source)
    raise MarketData::Error, "no bars cached" if daily.size.zero?

    @counts ||= Array.new(steps.size) { Hash.new(0) }
    @with_data = @with_data.to_i + 1
    features = Features.for(daily)
    steps.each_with_index do |(_, c), i|
      outcome = ScreenSpec.check(c, features)
      @counts[i][outcome] += 1
      return unless outcome == :pass
    end

    matches.create!(
      symbol: symbol,
      details: features.slice(*fields_used),
      why: conditions.map { _1.explain(features) }.join(" · ")
    )
  end

  private
    def understood_something
      return if conditions.any?

      # Recognized but refused (an EMA, revenue growth...): say why. Not recognized at all: a hint.
      refused = not_screened.reject { _1["reason"] == ScreenParser::NO_RULE }
      if refused.any?
        # Show people the reasons; a raw model proposal (JSON) belongs in the audit spec, not the message.
        items = refused.map { |item| item["text"].to_s.lstrip.start_with?("{", "[") ? item["reason"] : "#{item["text"]} (#{item["reason"]})" }
        errors.add(:base, "Nothing in that can be screened here: " + items.uniq.join("; "))
      else
        errors.add(:base, "I couldn't turn that into any screen conditions. Try e.g. \"RSI under 30\".")
      end
    end

    def adopt_universe(universe, unmapped)
      universe = universe.respond_to?(:to_h) ? universe.to_h.stringify_keys : {}
      if (problems = ScreenSpec.universe_problems(universe)).any?
        unmapped << { "text" => universe.to_json, "reason" => problems.join("; ") }
        return {}
      end
      universe.select do |key, value|
        next true if ScreenSpec::UNIVERSE_FILTERS.key?(key)

        unmapped << { "text" => "#{key.humanize}: #{Array(value).join(", ")}",
                      "reason" => "the universe here is a fixed list of #{Universe.symbols.size} large US stocks; sectors, industries and market caps aren't loaded" }
        false
      end
    end

    # The proposed ranking, if it is valid and computable here; otherwise the default.
    def adopt_rank(rank, accepted)
      valid = Array(rank).filter_map do |r|
        r = r.to_h.stringify_keys if r.respond_to?(:to_h)
        next if ScreenSpec.rank_problems(r).any? || ScreenSpec.unavailable_reason(r["field"])
        { "field" => r["field"], "direction" => r["direction"], "weight" => r.fetch("weight", 1) }
      end
      valid.presence || ScreenSpec.default_rank(accepted)
    end

    def adopt_top_n(top_n) = top_n.is_a?(Integer) && (1..ScreenSpec::MAX_TOP_N).cover?(top_n) ? top_n : ScreenSpec::DEFAULT_TOP_N

    # The fields a match keeps: those its conditions and its ranking read, plus the tie-break.
    def fields_used
      (conditions.flat_map { [ _1.field, _1.ref ] } + spec.fetch("rank", []).pluck("field") + %w[close avg_dollar_volume_50d]).compact.uniq
    end

    def funnel_rows
      start = { "step" => "#{@with_data.to_i} stocks with prices", "kind" => "start",
                "n_in" => @with_data.to_i, "n_pass" => @with_data.to_i, "n_fail" => 0, "n_missing" => 0 }
      [ start ] + steps.each_with_index.map do |(label, _), i|
        counts = @counts[i]
        { "step" => label, "kind" => i < steps.size - conditions.size ? "universe" : "condition",
          "n_in" => counts.values.sum, "n_pass" => counts[:pass], "n_fail" => counts[:fail], "n_missing" => counts[:missing] }
      end
    end

    # EquityScout's ranking: weighted mean of percentile ranks; ties go to the more liquid
    # name (EquityScout uses market cap, which isn't loaded here), then the ticker.
    def rank_matches
      rows = matches.to_a.map { [ _1, _1.details ] }
      scores = ScreenSpec.scores(rows, spec.fetch("rank"))
      rows.sort_by { |match, details| [ -scores[match], -details.fetch("avg_dollar_volume_50d", 0), match.symbol ] }
          .each.with_index(1) { |(match, _), rank| match.update_columns(score: scores[match], rank: rank) }
    end
end
