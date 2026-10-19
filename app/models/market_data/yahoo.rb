require "net/http"

# Free daily prices from Yahoo's (unofficial) chart API. Prices are split-adjusted;
# dividends are not taken out. Fine for a demo; a real desk would use a licensed feed.
module MarketData::Yahoo
  URL = "https://query1.finance.yahoo.com/v8/finance/chart/%s"

  # Returns an array of { date:, open:, high:, low:, close:, volume: } hashes.
  def self.fetch(symbol, range: "2y")
    uri = URI(format(URL, URI.encode_www_form_component(symbol)))
    uri.query = URI.encode_www_form(range: range, interval: "1d")
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 10) do |http|
      http.get(uri.request_uri, "User-Agent" => "Mozilla/5.0 (rails-nl-screen)")
    end
    raise MarketData::Error, "Yahoo HTTP #{response.code} for #{symbol}" unless response.is_a?(Net::HTTPSuccess)

    parse(response.body, symbol)
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
    raise MarketData::Error, "Yahoo unreachable for #{symbol}: #{e.message}"
  end

  def self.parse(body, symbol)
    result = JSON.parse(body).dig("chart", "result", 0)
    raise MarketData::Error, "Yahoo returned no data for #{symbol}" unless result && result["timestamp"]

    offset = result.dig("meta", "gmtoffset").to_i
    quote = result.dig("indicators", "quote", 0)
    result["timestamp"].each_with_index.filter_map do |ts, i|
      open, high, low, close, volume = %w[open high low close volume].map { |k| quote[k][i] }
      next if [ open, high, low, close ].any?(&:nil?) # Yahoo leaves holes on halted/partial days

      { date: Time.at(ts + offset).utc.to_date, open: open, high: high, low: low, close: close, volume: volume.to_i }
    end
  rescue JSON::ParserError
    raise MarketData::Error, "Yahoo returned something that isn't JSON for #{symbol}"
  end
end
