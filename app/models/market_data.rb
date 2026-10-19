# Where daily bars come from. Stooq (free CSV) by default; set
# MARKET_DATA=synthetic to use deterministic fake prices when offline.
module MarketData
  class Error < StandardError; end

  def self.source
    ENV["MARKET_DATA"] == "synthetic" ? Synthetic : Stooq
  end
end
