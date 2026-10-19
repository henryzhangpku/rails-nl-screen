require "zlib"

# Deterministic fake daily bars (a random walk seeded by the symbol), so the
# whole app runs with no network. Same symbol + same day => same prices.
module MarketData::Synthetic
  def self.fetch(symbol, days: 500)
    rng = Random.new(Zlib.crc32(symbol))
    price = 20 + rng.rand(300.0)
    base_volume = 1_000_000 + rng.rand(20_000_000)
    dates = (0..(days * 1.5).to_i).map { |i| Date.current - i }.reject { |d| d.saturday? || d.sunday? }.first(days).reverse

    dates.map do |date|
      open = price
      price *= Math.exp(rng.rand(-0.03..0.031))
      { date: date, open: open.round(2), high: ([ open, price ].max * (1 + rng.rand(0.01))).round(2),
        low: ([ open, price ].min * (1 - rng.rand(0.01))).round(2), close: price.round(2),
        volume: (base_volume * rng.rand(0.5..2.0)).to_i }
    end
  end
end
