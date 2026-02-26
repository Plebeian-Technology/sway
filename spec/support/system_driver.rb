# frozen_string_literal: true

module SystemBrowserPreflight
  module_function

  CHROME_CANDIDATES = %w[
    /usr/bin/chromium
    /usr/bin/chromium-browser
    /usr/bin/google-chrome
    /usr/bin/google-chrome-stable
  ].freeze

  CHROMEDRIVER_CANDIDATES = %w[
    /usr/bin/chromedriver
    /usr/lib/chromium/chromedriver
  ].freeze

  def chrome_binary
    CHROME_CANDIDATES.find { |path| File.executable?(path) }
  end

  def chromedriver_binary
    CHROMEDRIVER_CANDIDATES.find { |path| File.executable?(path) }
  end

  def available?
    chrome_binary && chromedriver_binary
  end

  def missing_requirements_message
    <<~MSG
      System JS specs require both a browser and chromedriver in the rspec container.
      Missing browser: #{chrome_binary.nil?}
      Missing chromedriver: #{chromedriver_binary.nil?}

      Try rebuilding test images:
        dip compose build rspec
      Then re-run:
        dip run bundle exec rspec spec/system/...
    MSG
  end

  def log_status_once(reporter: RSpec.configuration.reporter)
    return if @status_logged

    if available?
      reporter.message(
        "[system-driver] Selenium system specs enabled (browser: #{chrome_binary}, chromedriver: #{chromedriver_binary})",
      )
    else
      reporter.message(
        "[system-driver] Selenium system specs skipped. #{missing_requirements_message.strip}",
      )
    end

    @status_logged = true
  end

  def assert_available!
    return if available?

    raise missing_requirements_message
  end
end

Capybara.register_driver :selenium_chromium_headless do |app|
  chrome_binary = SystemBrowserPreflight.chrome_binary
  chromedriver_binary = SystemBrowserPreflight.chromedriver_binary

  options = Selenium::WebDriver::Chrome::Options.new
  options.binary = chrome_binary if chrome_binary
  service =
    (
      if chromedriver_binary
        Selenium::WebDriver::Service.chrome(path: chromedriver_binary)
      else
        nil
      end
    )

  %w[
    --headless=new
    --disable-gpu
    --no-sandbox
    --disable-dev-shm-usage
    --window-size=1400,1400
  ].each { |arg| options.add_argument(arg) }

  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    options: options,
    service: service,
  )
end

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :rack_test }

  config.before(:each, type: :system, js: true) do
    SystemBrowserPreflight.log_status_once
    unless SystemBrowserPreflight.available?
      skip(SystemBrowserPreflight.missing_requirements_message)
    end

    driven_by :selenium_chromium_headless
  end
end
