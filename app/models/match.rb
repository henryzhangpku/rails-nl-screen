# A symbol that passed every condition of a screen, with the observed values.
class Match < ApplicationRecord
  belongs_to :screen

  # Turbo Streams: append the new row to the results table of anyone viewing the screen.
  after_create_commit -> { broadcast_append_to screen, target: "matches" }
end
