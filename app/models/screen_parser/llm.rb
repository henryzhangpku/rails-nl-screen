# Optional: ask an LLM to *propose* the screen spec as JSON (the contract shared with
# EquityScout, see ScreenSpec). The proposal goes through exactly the same checks as
# the rule-based parser's, so the model can suggest but only code decides.
#
# Any provider RubyLLM supports works: the provider follows from the model name
# (deepseek-* -> DeepSeek, gpt-* -> OpenAI, gemini-* -> Gemini, ...).
# The model is the prompt version's (edit it at /prompts), or SCREEN_PARSER_MODEL.
# Used only when that provider's API key is set (config/initializers/ruby_llm.rb).
module ScreenParser::LLM
  MODEL = "deepseek-v4-flash"

  # Raised for a reply the parser can't use at all; Screen falls back to the rules.
  class Error < StandardError; end
  class IncompleteResponse < Error; end # the model stopped before finishing (length, content filter, ...)
  class MalformedResponse < Error; end  # no conditions array in the reply

  NULLABLE_NUMBER = { anyOf: [ { type: "number" }, { type: "null" } ] }.freeze

  # The screen spec as a JSON schema (strict-mode friendly: every key present, null for
  # "not used"). Field and operator enums come from ScreenSpec, so the model can only
  # name whitelisted fields; ScreenSpec still validates every value it sends.
  SCHEMA = {
    type: "object",
    additionalProperties: false,
    required: %w[conditions rank universe top_n unmapped notes],
    properties: {
      conditions: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: %w[field op value ref why],
          properties: {
            field: { type: "string", enum: ScreenSpec::FIELDS.keys },
            op:    { type: "string", enum: ScreenSpec::OPS },
            value: { anyOf: [ { type: "number" }, { type: "boolean" }, { type: "array", items: { type: "number" } }, { type: "null" } ] },
            ref:   { anyOf: [ { type: "string", enum: ScreenSpec::FIELDS.keys }, { type: "null" } ] },
            why:   { type: "string" }
          }
        }
      },
      rank: {
        type: "array",
        items: {
          type: "object",
          additionalProperties: false,
          required: %w[field direction weight],
          properties: {
            field: { type: "string", enum: ScreenSpec::FIELDS.keys },
            direction: { type: "string", enum: %w[asc desc] },
            weight: { type: "number" }
          }
        }
      },
      universe: {
        type: "object",
        additionalProperties: false,
        required: ScreenSpec::UNIVERSE_KEYS,
        properties: ScreenSpec::UNIVERSE_KEYS.to_h do |key|
          [ key, key.match?(/sectors|groups|industries|themes/) ? { anyOf: [ { type: "array", items: { type: "string" } }, { type: "null" } ] } : NULLABLE_NUMBER ]
        end
      },
      top_n: { type: "integer" },
      unmapped: {
        type: "array",
        items: {
          type: "object", additionalProperties: false, required: %w[text reason],
          properties: { text: { type: "string" }, reason: { type: "string" } }
        }
      },
      notes: { type: "string" }
    }
  }.freeze

  # EquityScout's prompt (schema_for_prompt there), from the same field list.
  SYSTEM_PROMPT = <<~PROMPT
    You translate a plain-English stock screen into a screen spec. Fill the JSON spec; code validates
    every field, operator, unit and threshold against a whitelist and refuses anything else.

    FIELDS (name | kind | meaning):
    #{ScreenSpec::FIELDS.values.reject { _1.name.start_with?("rs_") }.map { "  #{_1.name} | #{_1.kind} | #{_1.desc}" }.join("\n")}
      rs_{1,3,6,12}m_vs_{#{ScreenSpec::BENCHMARKS.keys.join(",")}} | ratio | relative return vs that benchmark ETF

    RULES:
    - A condition is {field, op, value, ref, why}: op is one of #{ScreenSpec::OPS.join(" ")}; give a number `value`
      (a [low, high] pair for between, true/false with == for boolean fields) OR a `ref` field to compare with; the other is null.
    - Ratios are decimals: 0.10 means 10%. "20% below the 52-week high" -> drawdown_52w <= -0.20;
      "within 5% of the high" -> drawdown_52w >= -0.05. Money is in US dollars.
    - Fields ending in _w use weekly closes; every other technical field uses daily bars. "MACD crossing above its
      signal" -> macd_cross_up == true (daily) or macd_cross_up_w == true (weekly); "MACD above its signal" -> macd_hist > 0;
      "volume above its 20-day average" -> volume_ratio_20d > 1; "price above the 200-day average" -> close > ref sma200.
    - rank: 1-3 {field, direction, weight} entries that order the survivors (e.g. rsi14 asc for "most oversold").
    - universe: only the keys the user asked for; null for the rest. top_n: 1-#{ScreenSpec::MAX_TOP_N}, default #{ScreenSpec::DEFAULT_TOP_N}.
    - Anything the fields cannot express (analyst ratings, guidance, sentiment, an EMA, a MACD cross down) goes in
      `unmapped` as {text, reason}. Never invent a condition or approximate one.
    Reply with only the JSON object.
  PROMPT

  # Stored with the prompt in PromptEngine, so the seeds can tell a prompt written for an
  # older contract and replace it (as a new version).
  CONTRACT = "screen-spec v#{ScreenSpec::VERSION}"

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
    raise IncompleteResponse, "#{request.model} stopped early (#{response.finish_reason})" unless response.finish_reason.in?([ :stop, nil ])

    # Not every provider/protocol enforces SCHEMA (DeepSeek's chat completions only promise
    # *a* JSON object), so read it defensively. No conditions array means no usable reply;
    # otherwise Screen#adopt checks every part against the contract, while the raw
    # proposal is kept for the audit view. Nulls mean "not used", so they're dropped.
    json = response.parsed.is_a?(Hash) ? response.parsed : {}
    conditions = json["conditions"]
    raise MalformedResponse, "#{request.model} replied without a conditions array" unless conditions.is_a?(Array)

    ScreenParser::Result.new(
      conditions: conditions.map { _1.is_a?(Hash) ? _1.compact : _1 },
      unmapped: Array(json["unmapped"]),
      rank: Array(json["rank"]),
      universe: json["universe"].is_a?(Hash) ? json["universe"].compact : {},
      top_n: json["top_n"]
    )
  end
end
