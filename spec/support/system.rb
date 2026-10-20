require "capybara/cuprite"

# System specs drive headless Chrome through Cuprite (Chrome DevTools Protocol, no chromedriver).
# Set BROWSER_PATH to use a specific Chrome/Chromium build.
# Chrome's sandbox is off in CI (CI is set there) or with CHROME_NO_SANDBOX=1, e.g. in a container;
# and always as root, where Chrome refuses to start with it.
no_sandbox = ENV["CI"].present? || ENV["CHROME_NO_SANDBOX"].present? || Process.uid.zero?

Capybara.register_driver(:nl_cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    window_size: [ 1400, 1000 ],
    browser_path: ENV["BROWSER_PATH"],
    browser_options: no_sandbox ? { "no-sandbox" => nil } : {},
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
