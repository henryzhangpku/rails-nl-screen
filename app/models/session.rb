# == Schema Information
#
# Table name: sessions
# Database name: primary
#
#  id         :integer          not null, primary key
#  ip_address :string
#  user_agent :string
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_sessions_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Session < ApplicationRecord
  LIFETIME = 30.days # then sign in again; the cookie expires at the same time

  belongs_to :user

  scope :active, -> { where(created_at: LIFETIME.ago..) }
end
