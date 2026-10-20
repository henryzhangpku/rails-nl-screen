require "webmock/rspec"

# No spec may reach the internet: external APIs are stubbed per spec.
# Localhost stays open for system specs (Capybara's server and the browser driver).
WebMock.disable_net_connect!(allow_localhost: true)
