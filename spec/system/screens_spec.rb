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

  it "shows what was understood, then the ranked results" do
    visit root_path
    click_on "within 5% of the 52-week high, price above the 50-day EMA, volume 1.5x its 20-day average"
    click_on "Run screen"

    expect(page).to have_text("Here's what I understood", wait: 60) # the inline job scans all 100 symbols first
    expect(page).to have_css(".ns-chip", text: "Drawdown from 52-week high below 5%")
    expect(page).to have_css(".ns-chip", text: "Price above EMA(50)")
    expect(page).to have_css(".ns-chip", text: "Volume above 1.5x its 20-bar average")
    expect(page).to have_css("#progress", text: "Done")

    Screen.last.matches.each do |match|
      expect(page).to have_css("#matches tr", text: match.symbol)
    end
  end
end
