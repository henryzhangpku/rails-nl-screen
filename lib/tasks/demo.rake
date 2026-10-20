# Builds a static, read-only snapshot of the app for GitHub Pages:
#
#   bin/rails demo:export            # writes tmp/site/index.html, screen-1.html, ...
#
# It runs each Screen::EXAMPLES query exactly like RunScreenJob would, then renders
# the views outside of any request with ApplicationController.render.
SITE_URL = "https://henryzhangpku.github.io/rails-nl-screen/"

# Screenshots the 1200x627 link-preview card (og.png) with headless Chrome.
# Best effort: without Chrome the site still builds, just without a preview image.
def write_preview_image(out, html)
  require "selenium-webdriver"
  Selenium::WebDriver::Chrome::Service.driver_path = ENV["CHROMEDRIVER_PATH"] if ENV["CHROMEDRIVER_PATH"]
  card = out.join("og-card.html")
  File.write(card, html)
  options = Selenium::WebDriver::Chrome::Options.new(args: %w[--headless=new --hide-scrollbars --window-size=1200,627])
  options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"]
  options.add_argument("--no-sandbox") if Process.uid.zero?
  browser = Selenium::WebDriver.for(:chrome, options: options)
  browser.execute_cdp("Emulation.setDeviceMetricsOverride", width: 1200, height: 627, deviceScaleFactor: 1, mobile: false)
  browser.navigate.to "file://#{card}"
  20.times { break if browser.execute_script("return document.fonts.status") == "loaded"; sleep 0.25 }
  browser.save_screenshot(out.join("og.png").to_s)
  puts "Wrote og.png"
rescue => e
  puts "Skipped og.png (#{e.class}: #{e.message.lines.first&.strip})"
ensure
  browser&.quit
  FileUtils.rm_f(card) if card
end

namespace :demo do
  desc "Run the example screens and write static HTML to tmp/site"
  task export: :environment do
    out = Rails.root.join("tmp/site")
    FileUtils.rm_rf(out)
    FileUtils.mkdir_p(out)

    # Prefer real prices; fall back to synthetic ones if the source is unreachable.
    source = MarketData.source
    begin
      source.fetch("AAPL")
    rescue MarketData::Error => e
      puts "Real prices unavailable (#{e.message}); using synthetic prices"
      source = MarketData::Synthetic
    end
    data_source = source == MarketData::Synthetic ? "synthetic (simulated) prices" : "real daily prices (Yahoo chart API)"

    screens = Screen::EXAMPLES.map do |query|
      screen = Screen.from_query(query, parser: ScreenParser)
      screen.save!
      screen.run(source: source)
      puts "#{screen.matches.size.to_s.rjust(3)} matches: #{query}"
      screen
    end

    assigns = { built_on: Date.current, data_source: data_source, site_url: SITE_URL }
    render = lambda do |template, extra|
      html = ApplicationController.render(template: template, layout: "demo", assigns: assigns.merge(extra))
      html.gsub(/<!-- (BEGIN|END) app\/views.*?-->\n?/m, "") # development's view-filename annotations
    end

    File.write(out.join("index.html"), render.("demo/index", screens: screens, page_path: ""))
    screens.each_with_index do |screen, i|
      File.write(out.join("screen-#{i + 1}.html"), render.("demo/screen", screen: screen, page_path: "screen-#{i + 1}.html"))
    end
    write_preview_image(out, ApplicationController.render(template: "demo/og", layout: false, assigns: assigns.merge(screens: screens)))
    screens.each(&:destroy) # don't leave demo runs in your "Recent screens"
    puts "Wrote #{screens.size + 1} pages to #{out}"
  end
end
