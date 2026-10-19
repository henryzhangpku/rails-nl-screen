# Builds a static, read-only snapshot of the app for GitHub Pages:
#
#   bin/rails demo:export            # writes tmp/site/index.html, screen-1.html, ...
#
# It runs each Screen::EXAMPLES query exactly like RunScreenJob would, then renders
# the views outside of any request with ApplicationController.render.
namespace :demo do
  desc "Run the example screens and write static HTML to tmp/site"
  task export: :environment do
    out = Rails.root.join("tmp/site")
    FileUtils.rm_rf(out)
    FileUtils.mkdir_p(out)

    # Prefer real Stooq prices; fall back to synthetic ones if Stooq is unreachable.
    source = MarketData.source
    begin
      source.fetch("AAPL")
    rescue MarketData::Error => e
      puts "Stooq unavailable (#{e.message}); using synthetic prices"
      source = MarketData::Synthetic
    end
    data_source = source == MarketData::Synthetic ? "synthetic (simulated) prices" : "real daily prices from Stooq"

    screens = Screen::EXAMPLES.map do |query|
      screen = Screen.from_query(query, parser: ScreenParser)
      screen.save!
      screen.run(source: source)
      puts "#{screen.matches.size.to_s.rjust(3)} matches: #{query}"
      screen
    end

    assigns = { built_on: Date.current, data_source: data_source }
    render = ->(template, extra) { ApplicationController.render(template: template, layout: "demo", assigns: assigns.merge(extra)) }

    File.write(out.join("index.html"), render.("demo/index", screens: screens))
    screens.each_with_index do |screen, i|
      File.write(out.join("screen-#{i + 1}.html"), render.("demo/screen", screen: screen))
    end
    screens.each(&:destroy) # don't leave demo runs in your "Recent screens"
    puts "Wrote #{screens.size + 1} pages to #{out}"
  end
end
