# Runs a screen in the background (Solid Queue). Matches stream to the browser
# from Match's after_create_commit broadcast.
class RunScreenJob < ApplicationJob
  queue_as :default

  # The screen was deleted before the job ran (GlobalID can't find it): nothing to do.
  discard_on ActiveJob::DeserializationError

  # A single symbol's fetch error is skipped inside Screen#run; MarketData::Error gets
  # here only when no symbol had data, which usually means the source is down. Screen#run
  # starts over, so a retry can't duplicate matches.
  retry_on MarketData::Error, wait: :polynomially_longer, attempts: 3

  def perform(screen)
    screen.run
  end
end
