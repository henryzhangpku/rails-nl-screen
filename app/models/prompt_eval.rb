# Runs a PromptEngine eval set against one version of the screen parser's prompt,
# recording an EvalRun with one EvalResult per test case, so PromptEngine's admin
# can show pass rates, compare runs and chart them by version.
#
# PromptEngine's own runner sends evals to OpenAI's Evals API and grades by exact
# string match. This one calls Claude through the same code path as a real screen
# and grades what the code *accepts* (see .expected_output), so formatting
# differences in the model's JSON don't count as failures.
class PromptEval
  CASES_FILE = Rails.root.join("db/evals/screen_parser.yml")
  SET_NAME = "Example screens"

  # One line per accepted condition, sorted, plus a marker when part of the
  # query was reported as not understood. Same shape as a test case's expected_output.
  def self.expected_output(labels, unrecognized: false)
    (labels.sort + (unrecognized ? [ "(reports something it didn't understand)" ] : [])).join("\n")
  end

  def self.output_for(result)
    screen = Screen.new
    labels = result.conditions.filter_map do |attrs|
      condition = Condition.new(attrs.slice(*Screen::ATTRIBUTES).merge(screen: screen))
      condition.label if condition.valid?
    end
    expected_output(labels, unrecognized: result.unrecognized.any?)
  end

  def self.cases = YAML.load_file(CASES_FILE)

  # Idempotent: syncs the cases from CASES_FILE into the prompt's eval set, keyed by
  # query, so unchanged cases (and the results recorded against them) are kept.
  def self.load_set(prompt)
    prompt.eval_sets.find_or_create_by!(name: SET_NAME) do |set|
      set.description = "The example queries, graded on the conditions the code accepts. Run with bin/rails prompts:eval."
      set.grader_type = "exact_match"
    end.tap do |set|
      cases.each do |c|
        set.test_cases.find_or_initialize_by(description: c["query"])
           .update!(input_variables: { "query" => c["query"] },
                    expected_output: expected_output(c["expected"], unrecognized: c["unrecognized"]))
      end
      set.test_cases.where.not(description: cases.pluck("query")).destroy_all
    end
  end

  def initialize(eval_set, version: eval_set.prompt.current_version, chat: nil)
    @eval_set, @version, @chat = eval_set, version, chat
  end

  def run
    eval_run = @eval_set.eval_runs.create!(prompt_version: @version, status: :running, started_at: Time.current)
    results = @eval_set.test_cases.map { |test_case| grade(eval_run, test_case) }
    passed = results.count(&:passed)
    eval_run.update!(status: :completed, completed_at: Time.current,
                     total_count: results.size, passed_count: passed, failed_count: results.size - passed)
    eval_run
  end

  private
    def grade(eval_run, test_case)
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      result = ScreenParser::Claude.parse(test_case.input_variables["query"], version: @version, chat: @chat)
      output = self.class.output_for(result)
      record(eval_run, test_case, started, actual_output: output, passed: output == test_case.expected_output)
    rescue => e
      record(eval_run, test_case, started, error_message: "#{e.class}: #{e.message}", passed: false)
    end

    def record(eval_run, test_case, started, **attrs)
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      eval_run.eval_results.create!(test_case: test_case, execution_time_ms: elapsed_ms, **attrs)
    end
end
