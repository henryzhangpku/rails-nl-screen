# One rule of a Screen, in the screen-spec contract shared with EquityScout:
# a whitelisted field, an operator, and a threshold value or another field,
# e.g. {field: "rsi14", op: "<", value: 30} or {field: "close", op: ">", ref: "sma200"}.
# ScreenSpec decides what is allowed and how it reads in plain English.
# == Schema Information
#
# Table name: conditions
# Database name: primary
#
#  id         :integer          not null, primary key
#  field      :string           not null
#  op         :string           not null
#  position   :integer          default(0), not null
#  ref        :string
#  value      :json
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  screen_id  :integer          not null
#
# Indexes
#
#  index_conditions_on_screen_id  (screen_id)
#
# Foreign Keys
#
#  screen_id  (screen_id => screens.id)
#
class Condition < ApplicationRecord
  belongs_to :screen

  validate :fits_spec

  def to_spec = { "field" => field, "op" => op, "value" => value, "ref" => ref }.reject { |key, v| v.nil? && key.in?(%w[value ref]) }

  def label = ScreenSpec.describe(to_spec)

  # :pass, :fail or :missing for one symbol's features.
  def check(features) = ScreenSpec.check(to_spec, features)

  # "Daily RSI (14) under 30: 27.4", for the "why it matched" line.
  def explain(features)
    observed = ScreenSpec.plain_value(field, features[field])
    observed += " vs #{ScreenSpec.plain_value(ref, features[ref])}" if ref
    "#{label}: #{observed}"
  end

  private
    def fits_spec
      ScreenSpec.condition_problems(to_spec).each { |problem| errors.add(:base, problem.delete_prefix("condition: ")) }
      [ field, ref ].compact.each do |name|
        reason = ScreenSpec.unavailable_reason(name) if ScreenSpec::FIELDS.key?(name)
        errors.add(:base, "#{name} #{reason}") if reason
      end
    end
end
