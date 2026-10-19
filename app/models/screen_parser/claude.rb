require "anthropic"

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

  def self.enabled? = ENV["ANTHROPIC_API_KEY"].present?

  def self.parse(text, client: Anthropic::Client.new)
    message = client.messages.create(
      model: MODEL,
      max_tokens: 4000,
      system_: SYSTEM_PROMPT,
      output_config: { effort: :low, format_: { type: :json_schema, schema: SCHEMA } },
      messages: [ { role: "user", content: text } ]
    )
    raise "Claude declined (#{message.stop_reason})" unless message.stop_reason == :end_turn

    json = JSON.parse(message.content.find { |block| block.type == :text }.text)
    ScreenParser::Result.new(json["conditions"].map(&:symbolize_keys), json["unrecognized"])
  end
end
