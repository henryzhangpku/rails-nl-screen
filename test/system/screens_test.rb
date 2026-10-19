require "application_system_test_case"

class ScreensTest < ApplicationSystemTestCase
  # Run jobs inline and use synthetic prices, so the whole flow needs no network.
  setup do
    @adapter, ActiveJob::Base.queue_adapter = ActiveJob::Base.queue_adapter, :inline
    @market_data, ENV["MARKET_DATA"] = ENV["MARKET_DATA"], "synthetic"
  end

  teardown do
    ActiveJob::Base.queue_adapter = @adapter
    ENV["MARKET_DATA"] = @market_data
  end

  test "type a screen, see what was understood, see results" do
    visit root_path
    click_on "within 5% of the 52-week high, price above the 50-day EMA, volume 1.5x its 20-day average"
    click_on "Run screen"

    assert_text "Here's what I understood", wait: 60 # the inline job scans all 100 symbols first
    assert_selector ".understood code", text: "Drawdown from 52-week high below 5%"
    assert_selector ".understood code", text: "Price above EMA(50)"
    assert_selector ".understood code", text: "Volume above 1.5x its 20-bar average"
    assert_text(/Done: \d+ match(es)? out of 100 symbols/)

    Screen.last.matches.each do |match|
      assert_selector "#matches tr", text: match.symbol
    end
  end
end
