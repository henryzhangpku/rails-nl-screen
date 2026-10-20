# A symbol that passed every condition of a screen, with the observed values.
# == Schema Information
#
# Table name: matches
# Database name: primary
#
#  id         :integer          not null, primary key
#  details    :json             not null
#  score      :float            default(0.0), not null
#  symbol     :string           not null
#  why        :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  screen_id  :integer          not null
#
# Indexes
#
#  index_matches_on_screen_id_and_symbol  (screen_id,symbol) UNIQUE
#
# Foreign Keys
#
#  screen_id  (screen_id => screens.id)
#
class Match < ApplicationRecord
  belongs_to :screen, counter_cache: true # keeps screens.matches_count current

  validates :symbol, uniqueness: { scope: :screen_id } # backed by a unique index

  # Turbo Streams: append the new row to the results table of anyone viewing the screen.
  after_create_commit -> { broadcast_append_to screen, target: "matches" }
end
