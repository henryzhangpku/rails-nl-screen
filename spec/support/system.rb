# Headless Chrome via Selenium. Selenium finds Chrome and its driver itself;
# set CHROME_BIN / CHROMEDRIVER_PATH to point at specific builds instead.
RSpec.configure do |config|
  config.before(:each, type: :system) do
    Selenium::WebDriver::Chrome::Service.driver_path = ENV["CHROMEDRIVER_PATH"] if ENV["CHROMEDRIVER_PATH"]
    driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
      options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"]
      options.add_argument("--no-sandbox") if Process.uid.zero? # Chrome refuses to run as root (e.g. in containers)
    end
  end
end
