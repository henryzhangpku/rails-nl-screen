# Idempotent: bin/setup runs this once when it creates the database; rerun any time with bin/rails db:seed.

# The Claude screen parser's prompt, as a PromptEngine record. Editing it at /prompts
# creates a new numbered version; screens record which version parsed them.
PromptEngine::Prompt.find_or_create_by!(name: ScreenParser::Claude::PROMPT_NAME) do |prompt|
  prompt.description = "Turns a plain-English stock screen into whitelisted, typed conditions (JSON schema enforced in code)."
  prompt.system_message = ScreenParser::Claude::SYSTEM_PROMPT
  prompt.content = "{{query}}"
  prompt.model = ScreenParser::Claude::MODEL
  prompt.status = "active"
end

# One admin, for the prompt editor. Set ADMIN_PASSWORD (and optionally ADMIN_EMAIL);
# in development a local-only default is used so bin/setup just works.
password = ENV["ADMIN_PASSWORD"].presence || ("nl-screen-admin" if Rails.env.development?)
if password
  User.find_or_create_by!(email_address: ENV.fetch("ADMIN_EMAIL", "admin@example.com")) do |user|
    user.password = password
  end
end
