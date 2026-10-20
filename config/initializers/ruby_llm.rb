# RubyLLM: one client API across LLM providers. Only used when ANTHROPIC_API_KEY is set
# (see ScreenParser::Claude); the app works fully without it.
RubyLLM.configure do |config|
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"]
end
