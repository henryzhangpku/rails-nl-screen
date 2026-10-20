# RubyLLM: one client API across LLM providers (Ruby's LiteLLM). The screen parser
# uses whichever provider its model belongs to (see ScreenParser::LLM), when that
# provider's key is set; the app works fully without any of them.
RubyLLM.configure do |config|
  config.deepseek_api_key = ENV["DEEPSEEK_API_KEY"]
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.gemini_api_key = ENV["GEMINI_API_KEY"]
  config.openrouter_api_key = ENV["OPENROUTER_API_KEY"]
end
