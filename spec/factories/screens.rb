FactoryBot.define do
  factory :screen do
    query { "RSI under 30" }
    source { "rules" }
    parser { "rules v1" }
    status { "done" }
    universe_size { 100 }
    scanned_count { 100 }

    # A screen must understand at least one condition to be valid.
    after(:build) do |screen|
      screen.conditions << build(:condition, screen: screen) if screen.conditions.empty?
    end

    trait :running do
      status { "running" }
      scanned_count { 40 }
    end

    trait :from_llm do
      source { "llm" }
      parser { "claude-sonnet-5-5, prompt 00000000" }
    end

    # create(:screen, :with_matches, matches: 3)
    trait :with_matches do
      transient { matches { 2 } }
      after(:create) do |screen, ctx|
        create_list(:match, ctx.matches, screen: screen)
        screen.reload
      end
    end
  end

  factory :condition do
    screen
    indicator { "rsi" }
    operator { "below" }
    period { 14 }
    value { 30 }
    timeframe { "daily" }
  end

  factory :match do
    screen
    sequence(:symbol) { |n| "SYM#{n}" }
    details { [ { "label" => "RSI(14) below 30", "observed" => "RSI(14) 25" } ] }
    why { "RSI(14) 25 < 30" }
    score { 0.5 }
  end
end
