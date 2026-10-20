require "rails_helper"

RSpec.describe PriceSeries do
  describe "#weekly" do
    it "resamples daily bars into Monday-start weeks" do
      monday = Date.new(2026, 10, 5)
      days = (0..6).map { |i| monday + i }.reject { |d| d.saturday? || d.sunday? } + [ monday + 7 ]
      series = described_class.new(days.each_with_index.map do |d, i|
        PriceSeries::Point.new(date: d, open: 10 + i, high: 20 + i, low: 5 - i, close: 15 + i, volume: 100)
      end)

      weekly = series.weekly
      expect(weekly.size).to eq 2
      expect(weekly.points.first).to have_attributes(date: monday + 4, open: 10, high: 24, low: 1, close: 19, volume: 500)
    end
  end
end
