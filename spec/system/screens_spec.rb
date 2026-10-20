require "rails_helper"

RSpec.describe "Running a screen", type: :system do
  # Run jobs inline and use synthetic prices, so the whole flow needs no network.
  around do |example|
    adapter, ActiveJob::Base.queue_adapter = ActiveJob::Base.queue_adapter, :inline
    market_data, ENV["MARKET_DATA"] = ENV["MARKET_DATA"], "synthetic"
    example.run
  ensure
    ActiveJob::Base.queue_adapter = adapter
    ENV["MARKET_DATA"] = market_data
  end

  it "shows what was understood, the funnel, then the ranked results" do
    visit root_path
    click_on "within 5% of the 52-week high, price above the 50-day average, volume 1.5x its 50-day average"
    click_on "Run screen"

    expect(page).to have_text("Here's what I understood", wait: 60) # the inline job scans all 100 symbols first
    expect(page).to have_css(".ns-chip", text: "Within 5% of 52-week high")
    expect(page).to have_css(".ns-chip", text: "Price above its 50-day average")
    expect(page).to have_css(".ns-chip", text: "Volume at least 1.5× its 50-day average")
    expect(page).to have_css("#progress", text: "Done")
    expect(page).to have_css("#funnel", text: "Price above its 50-day average")

    screen = Screen.last
    expect(screen.funnel.last["n_pass"]).to eq screen.matches.size
    screen.matches.each do |match|
      expect(page).to have_css("#matches tr", text: match.symbol)
    end
  end

  it "lists what it can't screen, with the reason" do
    visit root_path
    fill_in "screen[query]", with: "RSI under 70, price above the 21-day EMA"
    click_on "Run screen"

    expect(page).to have_css(".ns-unmapped", text: "there is no EMA field", wait: 60)
  end
end
