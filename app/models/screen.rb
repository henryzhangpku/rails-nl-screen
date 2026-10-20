# A plain-English query plus the typed conditions we understood from it.
# Running a screen scans the universe and records a Match per passing symbol.
class Screen < ApplicationRecord
  has_many :conditions, -> { order(:position) }, dependent: :destroy
  has_many :matches, -> { order(score: :desc, id: :asc) }, dependent: :destroy # ranked, strongest first

  enum :status, %w[pending running done failed].index_by(&:itself)
  SOURCES = %w[rules claude].freeze

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

  ATTRIBUTES = %i[indicator timeframe operator period value].freeze

  # Shown as "Try:" buttons on the form, and used to build the static demo.
  EXAMPLES = [
    "RSI(14) under 30 on the daily, MACD crossing up, volume above its 20-day average, price above the 200-day moving average",
    "within 5% of the 52-week high, price above the 50-day EMA, volume 1.5x its 20-day average",
    "down at least 20% from the 52-week high, RSI under 40, price between $20 and $200",
    "weekly RSI above 60 and price above the 30-week moving average on the weekly",
    "MACD crossing up, price above the 200-day moving average"
  ].freeze

  # Parse `query` into an unsaved Screen. Claude proposes when configured;
  # otherwise (or if it fails) the rule-based parser does. Either way each
  # proposed condition must pass Condition's validations to be kept.
  def self.from_query(query, parser: ScreenParser::Claude.enabled? ? ScreenParser::Claude : ScreenParser)
    screen = new(query: query.to_s.strip)
    proposal = screen.propose_with(parser)
    proposal.conditions.each do |attrs|
      condition = Condition.new(attrs.slice(*ATTRIBUTES).merge(screen: screen, position: screen.conditions.size))
      if condition.valid?
        screen.conditions << condition
      else
        screen.notes << "Dropped #{attrs.compact.values.join(" ")}: #{condition.errors.full_messages.to_sentence}"
      end
    end
    proposal.unrecognized.each { |clause| screen.notes << "Didn't understand \"#{clause}\"" }
    screen
  end

  def propose_with(parser)
    self.source = parser == ScreenParser ? "rules" : "claude"
    record_proposal(parser, parser.parse(query))
  rescue => e
    Rails.logger.warn("#{parser} failed: #{e.class}: #{e.message}")
    notes << "Claude was unavailable (#{e.class.name.demodulize}), so the rule-based parser was used"
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

  # Called from RunScreenJob. Scans every symbol, streaming matches as they're found.
  def run(symbols = Universe.symbols, source: MarketData.source)
    update!(status: :running, universe_size: symbols.size, scanned_count: 0)
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
        save!
        last_saved = Time.current
      end
    end
    notes << "No data for #{skipped.size} symbol(s): #{skipped.join(", ")}" if skipped.any?
    # The counter cache is incremented in SQL, so refresh the in-memory value before the final save.
    self.matches_count = matches.count
    update!(status: :done)
  rescue => e
    update!(status: :failed, error_message: e.message)
    raise
  end

  def scan(symbol, source: MarketData.source)
    daily = Bar.series_for(symbol, source: source)
    raise MarketData::Error, "no bars cached" if daily.size.zero?

    results = conditions.map { |condition| [ condition, condition.evaluate(daily.in(condition.timeframe)) ] }
    return unless results.all? { |_, evaluation| evaluation.passed }

    matches.create!(
      symbol: symbol,
      score: results.sum { |_, evaluation| evaluation.strength } / results.size,
      details: results.map { |condition, evaluation| { "label" => condition.label, "observed" => evaluation.observed } },
      why: results.map { |condition, evaluation| [ ("weekly" if condition.timeframe == "weekly"), evaluation.reason ].compact.join(" ") }.join(" · ")
    )
  end

  private
    def understood_something
      errors.add(:base, "I couldn't turn that into any screen conditions. Try e.g. \"RSI under 30\".") if conditions.empty?
    end
end
