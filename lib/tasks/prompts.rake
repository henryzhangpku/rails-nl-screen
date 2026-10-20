namespace :prompts do
  desc "Run the screen parser's eval set against a prompt version (VERSION=n, default: current). Needs the API key for the model's provider."
  task eval: :environment do
    abort "Set the API key for #{ScreenParser::LLM.request_for("").model} (e.g. DEEPSEEK_API_KEY): the evals call it." unless ScreenParser::LLM.enabled?

    prompt = PromptEngine::Prompt.find_by(slug: ScreenParser::LLM::PROMPT_NAME) or
      abort "No #{ScreenParser::LLM::PROMPT_NAME.inspect} prompt in this database. Run bin/rails db:seed first."
    version = ENV["VERSION"] ? prompt.versions.find_by!(version_number: ENV["VERSION"]) : prompt.current_version
    eval_run = PromptEval.new(PromptEval.load_set(prompt), version: version).run

    eval_run.eval_results.includes(:test_case).each do |result|
      puts "#{result.passed? ? "pass" : "FAIL"}  #{result.test_case.description}"
      puts "      #{(result.error_message || result.actual_output).gsub("\n", "\n      ")}" unless result.passed?
    end
    puts "v#{version.version_number}: #{eval_run.passed_count}/#{eval_run.total_count} passed. " \
         "Compare runs at /prompts/prompts/#{prompt.id}/eval_sets/#{eval_run.eval_set_id}"
  end
end
