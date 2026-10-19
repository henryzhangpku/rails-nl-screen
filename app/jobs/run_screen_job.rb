# Runs a screen in the background (Solid Queue). Matches stream to the browser
# from Match's after_create_commit broadcast.
class RunScreenJob < ApplicationJob
  queue_as :default

  def perform(screen)
    screen.run
  end
end
