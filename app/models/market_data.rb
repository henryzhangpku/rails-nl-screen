# Where daily bars come from. Yahoo's free chart API by default; set
# MARKET_DATA=synthetic to use deterministic fake prices when offline.
module MarketData
  class Error < StandardError; end

  def self.source
    ENV["MARKET_DATA"] == "synthetic" ? Synthetic : Yahoo
  end
end
