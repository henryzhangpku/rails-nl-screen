# Idempotent: bin/setup runs this once when it creates the database; rerun any time with bin/rails db:seed.

# The LLM screen parser's prompt, as a PromptEngine record. Editing it at /prompts
# creates a new numbered version; screens record which version parsed them.
prompt = PromptEngine::Prompt.find_or_create_by!(slug: ScreenParser::LLM::PROMPT_NAME) do |prompt|
  prompt.name = ScreenParser::LLM::PROMPT_NAME
  prompt.description = "Turns a plain-English stock screen into a screen spec (the contract shared with EquityScout; validated in code)."
  prompt.system_message = ScreenParser::LLM::SYSTEM_PROMPT
  prompt.content = "{{query}}"
  prompt.model = ScreenParser::LLM::MODEL
  prompt.metadata = { "contract" => ScreenParser::LLM::CONTRACT }
  prompt.status = "active"
end
# A prompt seeded for an older contract (or the old default model) is brought up to date.
# Saving makes a new prompt version, so the change is on record in the prompt's history,
# and an edited prompt for the current contract is left alone.
unless prompt.metadata.to_h["contract"] == ScreenParser::LLM::CONTRACT
  prompt.update!(system_message: ScreenParser::LLM::SYSTEM_PROMPT,
                 description: "Turns a plain-English stock screen into a screen spec (the contract shared with EquityScout; validated in code).",
                 metadata: prompt.metadata.to_h.merge("contract" => ScreenParser::LLM::CONTRACT))
end
prompt.update!(model: ScreenParser::LLM::MODEL) if prompt.model == "claude-sonnet-5-5"

# Its eval set: the cases in db/evals/screen_parser.yml. Run them with bin/rails prompts:eval.
PromptEval.load_set(prompt)

# One admin, for the prompt editor. Set ADMIN_PASSWORD (and optionally ADMIN_EMAIL);
# in development a local-only default is used so bin/setup just works.
password = ENV["ADMIN_PASSWORD"].presence || ("nl-screen-admin" if Rails.env.development?)
if password
  User.find_or_create_by!(email_address: ENV.fetch("ADMIN_EMAIL", "admin@example.com")) do |user|
    user.password = password
  end
end
