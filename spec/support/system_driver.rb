# frozen_string_literal: true

Capybara.register_driver :selenium_chromium_headless do |app|
  options = Selenium::WebDriver::Chrome::Options.new
  options.binary = "/usr/bin/chromium" if File.exist?("/usr/bin/chromium")
  service = nil

  service = Selenium::WebDriver::Service.chrome(path: "/usr/bin/chromedriver") if File.exist?("/usr/bin/chromedriver")

  %w[
    --headless=new
    --disable-gpu
    --no-sandbox
    --disable-dev-shm-usage
    --window-size=1400,1400
  ].each { |arg| options.add_argument(arg) }

  Capybara::Selenium::Driver.new(app, browser: :chrome, options: options, service: service)
end

RSpec.configure do |config|
  config.before(:each, type: :system) do
    driven_by :rack_test
  end

  config.before(:each, type: :system, js: true) do
    driven_by :selenium_chromium_headless
  end
end
