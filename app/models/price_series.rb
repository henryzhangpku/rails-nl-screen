# An ordered list of OHLCV points for one symbol, in one timeframe.
# Condition#evaluate only ever sees one of these.
class PriceSeries
  Point = Data.define(:date, :open, :high, :low, :close, :volume)

  attr_reader :points

  def self.from_bars(bars)
    new(bars.map { |b| Point.new(date: b.date, open: b.open, high: b.high, low: b.low, close: b.close, volume: b.volume) })
  end

  def initialize(points)
    @points = points.sort_by(&:date)
  end

  def dates   = points.map(&:date)
  def closes  = points.map(&:close)
  def volumes = points.map(&:volume)
  def size    = points.size

  def highs_since(date) = points.select { |p| p.date > date }.map(&:high)

  def in(timeframe) = timeframe == "weekly" ? weekly : self

  # Resample daily bars into weekly ones (Monday-start weeks).
  def weekly
    weeks = points.group_by { |p| p.date.beginning_of_week }.values
    PriceSeries.new(weeks.map do |days|
      Point.new(date: days.last.date, open: days.first.open, high: days.map(&:high).max,
                low: days.map(&:low).min, close: days.last.close, volume: days.sum(&:volume))
    end)
  end
end
