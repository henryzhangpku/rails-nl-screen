# Optional: ask Claude to *propose* the typed screen as JSON. The proposal goes
# through exactly the same Condition validations as the rule-based parser, so
# the model can suggest but only code decides. Used only if ANTHROPIC_API_KEY is set.
module ScreenParser::Claude
  MODEL = "claude-sonnet-5-5"

  SCHEMA = {
    type: "object",
    additionalProperties: false,
    required: %w[conditions unrecognized],
    properties: {
      conditions: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: %w[indicator timeframe operator period value],
          properties: {
            indicator: { type: "string", enum: Condition::SPECS.keys },
            timeframe: { type: "string", enum: Condition::TIMEFRAMES },
            operator:  { type: "string", enum: Condition::SPECS.values.flat_map { |s| s[:operators] }.uniq },
            period:    { anyOf: [ { type: "integer" }, { type: "null" } ] },
            value:     { anyOf: [ { type: "number" }, { type: "null" } ] }
          }
        }
      },
      unrecognized: { type: "array", items: { type: "string" } }
    }
  }.freeze

  SYSTEM_PROMPT = <<~PROMPT
    You translate a plain-English stock screen into typed conditions.
    Allowed indicators and their meaning:
    - rsi: RSI(period) compared to value (0-100). operators: below, above. Default period 14.
    - macd: MACD(12,26,9) line crossing its signal line. operators: crosses_up, crosses_down. period and value null.
    - sma / ema: latest close compared to the moving average of `period` bars. operators: above, below. value null.
    - volume: latest volume vs `value` times its `period`-bar average (value 1 = just the average). operators: above, below.
    - drawdown: percent below the 52-week high (value 0-100). "within 10% of the high" = below 10; "down 20% or more" = above 20.
    - price: latest close in dollars. operators: above, below. A range becomes two conditions.
    timeframe is "daily" unless the user asks for weekly.
    Put any part of the request you cannot express with these into `unrecognized`, verbatim. Never invent conditions.
  PROMPT

  # The prompt is data: PromptEngine stores it in the "screen-parser" record and keeps
  # every edit as a numbered version (edit it at /prompts once signed in). If that
  # record doesn't exist or isn't active, the prompt above is used as written.
  PROMPT_NAME = "screen-parser"

  # What gets sent: instructions, the user message, the model, and a label naming them.
  Request = Data.define(:instructions, :message, :model, :label)

  def self.enabled? = ENV["ANTHROPIC_API_KEY"].present?

  # The label is stored on every screen, so you can tell which prompt version
  # (or, without PromptEngine, which fingerprint of the in-code prompt) parsed it.
  # Pass a PromptEngine::PromptVersion to use that version instead of the active one
  # (that's how PromptEval compares versions).
  def self.request_for(text, version: nil)
    version ||= PromptEngine::Prompt.active.find_by(name: PROMPT_NAME)&.current_version
    return fallback_request(text) unless version

    model = version.model.presence || MODEL
    message = PromptEngine::VariableDetector.new(version.content).render(query: text)
    Request.new(version.system_message, message, model, "#{model}, prompt #{PROMPT_NAME} v#{version.version_number}")
  end

  def self.fallback_request(text)
    fingerprint = Digest::SHA256.hexdigest(SYSTEM_PROMPT + SCHEMA.to_json).first(8)
    Request.new(SYSTEM_PROMPT, text, MODEL, "#{MODEL}, prompt #{fingerprint}")
  end

  def self.label = request_for("").label

  # The chat is injectable so tests (or a different provider) can stand in.
  def self.parse(text, chat: nil, version: nil)
    request = request_for(text, version: version)
    chat ||= RubyLLM.chat(model: request.model, provider: :anthropic)
    response = chat.with_instructions(request.instructions).with_schema(SCHEMA).ask(request.message)
    raise "Claude stopped early (#{response.finish_reason})" unless response.finish_reason.in?([ :stop, nil ])

    json = response.parsed
    ScreenParser::Result.new(json["conditions"].map(&:symbolize_keys), json["unrecognized"])
  end
end
