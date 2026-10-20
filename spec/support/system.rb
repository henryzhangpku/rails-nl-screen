require "capybara/cuprite"

# System specs drive headless Chrome through Cuprite (Chrome DevTools Protocol, no chromedriver).
# Set BROWSER_PATH to use a specific Chrome/Chromium build.
Capybara.register_driver(:nl_cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1000 ],
    browser_path: ENV["BROWSER_PATH"],
    browser_options: Process.uid.zero? ? { "no-sandbox" => nil } : {}, # Chrome refuses to run as root otherwise
    process_timeout: 20,
    timeout: 15
  )
end

# Find fields by their aria-label too (the search box has no visible label).
Capybara.enable_aria_label = true

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :nl_cuprite
  end
end
