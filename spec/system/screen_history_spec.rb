require "rails_helper"

RSpec.describe "Screen history", type: :system do
  before do
    create(:screen, :with_matches, matches: 3, query: "RSI under 30, MACD crossing up", created_at: 2.days.ago)
    create(:screen, query: "within 5% of the 52-week high", created_at: 1.day.ago)
  end

  it "filters as you type, inside the frame, and updates the URL" do
    visit screens_path
    expect(page).to have_css("#screens tbody tr", count: 2)

    fill_in "Search queries", with: "macd"

    expect(page).to have_css("#screens tbody tr", count: 1)
    expect(page).to have_link("RSI under 30, MACD crossing up")
    expect(page).to have_current_path(/q=macd/)
  end

  it "sorts by a column header" do
    visit screens_path
    click_link "Matches"

    # Retrying matchers: the URL changes before the frame's new rows arrive, so
    # reading the rows once (page.all(...).map) can catch the old, detached ones.
    expect(page).to have_current_path(/sort=matches_count/)
    expect(page).to have_css("#screens tbody tr:first-child .ns-history__link", exact_text: "within 5% of the 52-week high")

    click_link "Matches"
    expect(page).to have_current_path(/direction=desc/)
    expect(page).to have_css("#screens tbody tr:first-child .ns-history__link", exact_text: "RSI under 30, MACD crossing up")
  end

  it "deletes a screen in place and shows a toast" do
    visit screens_path

    accept_confirm do
      within("tr", text: "within 5% of the 52-week high") { click_button "Delete" }
    end

    expect(page).to have_css(".ns-toast", text: "Deleted “within 5% of the 52-week high”")
    expect(page).to have_css("#screens tbody tr", count: 1)
    expect(page).to have_current_path(screens_path)
  end
end
