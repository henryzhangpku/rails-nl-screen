require "csv"
require "net/http"

# Free end-of-day prices: https://stooq.com/q/d/l/?s=aapl.us&i=d
module MarketData::Stooq
  URL = "https://stooq.com/q/d/l/"

  # Returns an array of { date:, open:, high:, low:, close:, volume: } hashes.
  def self.fetch(symbol, from: 2.years.ago.to_date)
    uri = URI(URL)
    uri.query = URI.encode_www_form(s: "#{symbol.downcase}.us", i: "d", d1: from.strftime("%Y%m%d"))
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri)
    end
    raise MarketData::Error, "Stooq HTTP #{response.code} for #{symbol}" unless response.is_a?(Net::HTTPSuccess)

    parse(response.body, symbol)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
    raise MarketData::Error, "Stooq unreachable for #{symbol}: #{e.message}"
  end

  def self.parse(csv, symbol)
    unless csv.start_with?("Date,")
      raise MarketData::Error, "Stooq returned no data for #{symbol}: #{csv.to_s.first(60).strip}"
    end

    CSV.parse(csv, headers: true).map do |row|
      { date: Date.parse(row["Date"]), open: row["Open"].to_f, high: row["High"].to_f,
        low: row["Low"].to_f, close: row["Close"].to_f, volume: row["Volume"].to_i }
    end
  end
end
