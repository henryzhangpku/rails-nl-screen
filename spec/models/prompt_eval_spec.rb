require "rails_helper"

RSpec.describe PromptEval do
  let(:prompt) do
    PromptEngine::Prompt.create!(name: ScreenParser::Claude::PROMPT_NAME, status: "active", model: ScreenParser::Claude::MODEL,
                                 system_message: ScreenParser::Claude::SYSTEM_PROMPT, content: "{{query}}")
  end
  let(:eval_set) { described_class.load_set(prompt) }

  # A stand-in chat that answers each query the way the rule-based parser would.
  let(:chat) do
    instance_double(RubyLLM::Chat).tap do |chat|
      allow(chat).to receive(:with_instructions).and_return(chat)
      allow(chat).to receive(:with_schema).and_return(chat)
      allow(chat).to receive(:ask) do |query|
        result = ScreenParser.parse(query)
        Struct.new(:finish_reason, :parsed).new(:stop, result.to_h.deep_stringify_keys)
      end
    end
  end

  it "has expected outputs the rule-based parser agrees with" do
    described_class.cases.each do |c|
      expect(described_class.output_for(ScreenParser.parse(c["query"])))
        .to eq(described_class.expected_output(c["expected"], unrecognized: c["unrecognized"])), c["query"]
    end
  end

  it "grades the accepted conditions, not the raw JSON" do
    terse   = ScreenParser::Result.new([ { indicator: "rsi", timeframe: "daily", operator: "below", period: nil, value: 30 } ], [])
    verbose = ScreenParser::Result.new([ { indicator: "rsi", timeframe: "daily", operator: "below", period: 14, value: 30.0 } ], [])
    invalid = ScreenParser::Result.new(terse.conditions + [ { indicator: "rsi", timeframe: "daily", operator: "below", value: 900 } ], [])

    expect([ terse, verbose, invalid ].map { described_class.output_for(_1) }.uniq).to eq [ "RSI(14) below 30" ]
  end

  it "loads the cases into a PromptEngine eval set, idempotently, keeping past results" do
    described_class.new(eval_set, chat: chat).run
    expect { described_class.load_set(prompt) }.not_to change { PromptEngine::EvalResult.count }

    expect(eval_set.test_cases.count).to eq described_class.cases.size
    expect(eval_set.test_cases.first.input_variables).to eq("query" => described_class.cases.first["query"])
  end

  it "records a completed run with one result per case against the prompt version" do
    eval_run = described_class.new(eval_set, chat: chat).run

    expect(eval_run).to be_completed
    expect(eval_run.prompt_version).to eq prompt.current_version
    expect([ eval_run.total_count, eval_run.passed_count ]).to eq [ described_class.cases.size ] * 2
    expect(eval_run.eval_results.map(&:passed)).to all(be true)
  end

  it "sends the chosen version's prompt, so old and new versions can be compared" do
    v1 = prompt.current_version
    prompt.update!(system_message: "A rewritten prompt")

    described_class.new(eval_set, version: v1, chat: chat).run
    expect(chat).to have_received(:with_instructions).with(ScreenParser::Claude::SYSTEM_PROMPT).at_least(:once)
    expect(chat).not_to have_received(:with_instructions).with("A rewritten prompt")
  end

  it "fails a case, keeping the error, when the model call raises" do
    allow(chat).to receive(:ask).and_raise(RubyLLM::Error, "overloaded")
    eval_run = described_class.new(eval_set, chat: chat).run

    expect(eval_run.passed_count).to eq 0
    expect(eval_run.eval_results.first.error_message).to include("overloaded")
  end
end
