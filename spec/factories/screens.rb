FactoryBot.define do
  factory :screen do
    query { "RSI under 30" }
    source { "rules" }
    parser { "rules v2" }
    status { "done" }
    universe_size { 100 }
    scanned_count { 100 }

    # A screen must understand at least one condition to be valid; its spec follows from them.
    after(:build) do |screen|
      screen.conditions << build(:condition, screen: screen) if screen.conditions.empty?
      if screen.spec.blank?
        specs = screen.conditions.map(&:to_spec)
        screen.spec = { "version" => 1, "observation" => screen.query, "universe" => {}, "conditions" => specs,
                        "rank" => ScreenSpec.default_rank(specs), "top_n" => 5, "unmapped" => [], "notes" => "" }
      end
    end

    trait :running do
      status { "running" }
      scanned_count { 40 }
    end

    trait :from_llm do
      source { "llm" }
      parser { "deepseek-v4-flash, prompt 00000000" }
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
    field { "rsi14" }
    op { "<" }
    value { 30 }
  end

  factory :match do
    screen
    sequence(:symbol) { |n| "SYM#{n}" }
    details { { "rsi14" => 25.0, "close" => 100.0, "avg_dollar_volume_50d" => 1e9 } }
    why { "Daily RSI (14) under 30: 25" }
    score { 0.5 }
    sequence(:rank) { |n| n }
  end
end
