# One day of OHLCV for one symbol. This table is our local cache of market data.
# == Schema Information
#
# Table name: bars
# Database name: primary
#
#  id         :integer          not null, primary key
#  close      :float            not null
#  date       :date             not null
#  high       :float            not null
#  low        :float            not null
#  open       :float            not null
#  symbol     :string           not null
#  volume     :integer          default(0), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
# Indexes
#
#  index_bars_on_symbol_and_date  (symbol,date) UNIQUE
#
class Bar < ApplicationRecord
  HISTORY = 2.years

  scope :for_symbol, ->(symbol) { where(symbol: symbol).where(date: HISTORY.ago.to_date..).order(:date) }

  # Cached daily bars for `symbol`, fetching from the market data source at most
  # once per symbol per day (the "fetched today" marker lives in Rails.cache,
  # which is Solid Cache, i.e. another SQLite table).
  def self.series_for(symbol, source: MarketData.source)
    Rails.cache.fetch([ "bars-fetched", source.name, symbol, Date.current ], expires_in: 12.hours) do
      import(symbol, source.fetch(symbol))
      true
    end
    PriceSeries.from_bars(for_symbol(symbol))
  end

  def self.import(symbol, rows)
    return if rows.empty?
    now = Time.current
    upsert_all(rows.map { |r| r.merge(symbol: symbol, created_at: now, updated_at: now) }, unique_by: %i[symbol date])
  end
end
