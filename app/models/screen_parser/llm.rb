# Optional: ask an LLM to *propose* the typed screen as JSON. The proposal goes
# through exactly the same Condition validations as the rule-based parser, so
# the model can suggest but only code decides.
#
# Any provider RubyLLM supports works: the provider follows from the model name
# (claude-* -> Anthropic, deepseek-* -> DeepSeek, gpt-* -> OpenAI, gemini-* -> Gemini).
# The model is the prompt version's (edit it at /prompts), or SCREEN_PARSER_MODEL.
# Used only when that provider's API key is set (config/initializers/ruby_llm.rb).
module ScreenParser::LLM
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
    Reply with only a JSON object: {"conditions": [{"indicator", "timeframe", "operator", "period", "value"}], "unrecognized": ["..."]}.
  PROMPT

  # The prompt is data: PromptEngine stores it in the record with slug "screen-parser" and keeps
  # every edit as a numbered version (edit it at /prompts once signed in). If that
  # record doesn't exist or isn't active, the prompt above is used as written.
  PROMPT_NAME = "screen-parser"

  # The wire protocol, where a provider's default can't enforce SCHEMA. DeepSeek's chat
  # completions only promise *a* JSON object; its Responses API takes a json_schema.
  PROTOCOLS = { "deepseek" => "responses" }.freeze

  # What gets sent: instructions, the user message, the model and its provider,
  # and a label naming them.
  Request = Data.define(:instructions, :message, :model, :provider, :protocol, :label)

  def self.enabled? = configured?(request_for("").provider)

  def self.configured?(provider)
    RubyLLM::Provider.providers[provider&.to_sym]&.configured?(RubyLLM.config) || false
  end

  # The label is stored on every screen, so you can tell which model and prompt
  # version (or, without PromptEngine, which fingerprint of the in-code prompt) parsed it.
  # Pass a PromptEngine::PromptVersion to use that version instead of the active one
  # (that's how PromptEval compares versions).
  def self.request_for(text, version: nil)
    version ||= PromptEngine::Prompt.active.find_by(slug: PROMPT_NAME)&.current_version
    return fallback_request(text) unless version

    metadata = version.metadata.to_h
    model = ENV["SCREEN_PARSER_MODEL"].presence || version.model.presence || MODEL
    provider = provider_for(model, metadata["provider"])
    message = PromptEngine::VariableDetector.new(version.content).render(query: text)
    Request.new(version.system_message, message, model, provider, protocol_for(provider, metadata["protocol"]),
                "#{model}, prompt #{PROMPT_NAME} v#{version.version_number}")
  end

  def self.fallback_request(text)
    model = ENV["SCREEN_PARSER_MODEL"].presence || MODEL
    provider = provider_for(model)
    fingerprint = Digest::SHA256.hexdigest(SYSTEM_PROMPT + SCHEMA.to_json).first(8)
    Request.new(SYSTEM_PROMPT, text, model, provider, protocol_for(provider), "#{model}, prompt #{fingerprint}")
  end

  # From RubyLLM's model registry; for a model it doesn't list, name the provider in
  # SCREEN_PARSER_PROVIDER or the prompt's metadata ({"provider": "deepseek"}).
  def self.provider_for(model, named = nil)
    (ENV["SCREEN_PARSER_PROVIDER"].presence || named.presence || RubyLLM.models.find(model).provider).to_s
  rescue RubyLLM::ModelNotFoundError
    nil
  end

  # SCREEN_PARSER_PROTOCOL or the prompt's metadata ({"protocol": "chat_completions"})
  # override the default; nil lets RubyLLM pick.
  def self.protocol_for(provider, named = nil)
    ENV["SCREEN_PARSER_PROTOCOL"].presence || named.presence || PROTOCOLS[provider]
  end

  def self.label = request_for("").label

  # The chat is injectable so tests (or a different provider) can stand in.
  def self.parse(text, chat: nil, version: nil)
    request = request_for(text, version: version)
    chat ||= RubyLLM.chat(model: request.model, provider: request.provider&.to_sym, protocol: request.protocol&.to_sym,
                          assume_model_exists: request.provider.present?)
    response = chat.with_instructions(request.instructions).with_schema(SCHEMA).ask(request.message)
    raise "#{request.model} stopped early (#{response.finish_reason})" unless response.finish_reason.in?([ :stop, nil ])

    # Not every provider/protocol enforces SCHEMA (DeepSeek's chat completions only promise
    # *a* JSON object), so read it defensively; the Condition validations do the rest.
    json = response.parsed.to_h
    ScreenParser::Result.new(Array(json["conditions"]).grep(Hash).map(&:symbolize_keys), Array(json["unrecognized"]).map(&:to_s))
  end
end
