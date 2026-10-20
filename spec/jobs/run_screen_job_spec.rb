require "rails_helper"

RSpec.describe RunScreenJob, type: :job do
  include ActiveJob::TestHelper

  let(:screen) { Screen.from_query("price above 1", parser: ScreenParser).tap(&:save!) }

  around do |example|
    ENV["MARKET_DATA"] = "synthetic"
    example.run
  ensure
    ENV.delete("MARKET_DATA")
  end

  before { allow(Universe).to receive(:symbols).and_return(%w[AAPL MSFT]) }

  it "runs the screen" do
    described_class.perform_now(screen)
    expect(screen.reload).to be_done
    expect(screen.matches.map(&:symbol)).to match_array %w[AAPL MSFT]
  end

  it "produces no duplicate matches when it runs twice" do
    2.times { described_class.perform_now(screen) }
    expect(Match.where(screen: screen).group(:symbol).count).to eq("AAPL" => 1, "MSFT" => 1)
    expect(screen.reload.matches_count).to eq 2
  end

  it "is discarded when the screen was deleted before it ran" do
    described_class.perform_later(screen)
    screen.destroy!

    expect { perform_enqueued_jobs }.not_to raise_error
    expect(enqueued_jobs).to be_empty
  end

  it "retries when no symbol had data, then gives up after 3 attempts" do
    allow(Bar).to receive(:series_for).and_raise(MarketData::Error, "Yahoo unreachable")

    described_class.perform_later(screen)
    perform_enqueued_jobs(only: described_class) # the first attempt fails and enqueues a retry
    expect(enqueued_jobs.size).to eq 1

    expect {
      2.times { perform_enqueued_jobs(only: described_class) }
    }.to raise_error(MarketData::Error)
    expect(screen.reload).to be_failed
  end
end
