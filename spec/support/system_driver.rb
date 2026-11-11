# frozen_string_literal: true

module SystemBrowserPreflight
  CHROME_CANDIDATES = [
    "/usr/bin/chromium",
    "/usr/bin/chromium-browser",
    "/usr/bin/google-chrome",
    "/usr/bin/google-chrome-stable",
    # macOS (host runs + the self-hosted CI runner)
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium"
  ].freeze

  CHROMEDRIVER_CANDIDATES = %w[
    /usr/bin/chromedriver
    /usr/lib/chromium/chromedriver
    /opt/homebrew/bin/chromedriver
  ].freeze

  def self.chrome_binary
    CHROME_CANDIDATES.find { |path| File.executable?(path) }
  end

  def self.chromedriver_binary
    CHROMEDRIVER_CANDIDATES.find { |path| File.executable?(path) }
  end

  # chromedriver is optional: when none of the known paths exist, the driver
  # below passes service: nil and selenium-webdriver's Selenium Manager fetches
  # a matching chromedriver by itself. That is what happens on a macOS host; the
  # dip rspec image ships /usr/bin/chromedriver, so nothing changes there.
  def self.available?
    !chrome_binary.nil?
  end

  def self.missing_requirements_message
    <<~MSG
      System JS specs require a Chrome/Chromium browser (chromedriver is
      resolved via Selenium Manager when no packaged binary is present).
      Missing browser: #{chrome_binary.nil?}
      Missing chromedriver (packaged): #{chromedriver_binary.nil?}

      In the rspec container, try rebuilding test images:
        dip compose build rspec
      Then re-run:
        dip run bundle exec rspec spec/system/...
    MSG
  end

  def self.log_status_once(reporter: RSpec.configuration.reporter)
    return if @status_logged

    if available?
      reporter.message(
        "[system-driver] Selenium system specs enabled (browser: #{chrome_binary}, chromedriver: #{chromedriver_binary})"
      )
    else
      reporter.message(
        "[system-driver] Selenium system specs skipped. #{missing_requirements_message.strip}"
      )
    end

    @status_logged = true
  end

  def self.assert_available!
    return if available?

    Kernel.raise(missing_requirements_message)
  end

  # @lat: [[verify-sh-lane-contract-design#Why the browser lane alone carries SWAY_REQUIRE_BROWSER=1]]
  def self.required?
    ENV["SWAY_REQUIRE_BROWSER"] == "1"
  end
end

Capybara.register_driver :selenium_chromium_headless do |app|
  chrome_binary = SystemBrowserPreflight.chrome_binary
  chromedriver_binary = SystemBrowserPreflight.chromedriver_binary

  # Sets the level FLOOR, not whether capture happens. Without it: WARNING+
  # only, 2 entries. With "ALL": every level, 14. Measured 2026-08-10.
  # So its real job is SWAY_BROWSER_CONSOLE_LEVEL=DEBUG. The gate in
  # browser_console_capture_spec.rb plants a console.debug for that reason.
  options = Selenium::WebDriver::Chrome::Options.new(logging_prefs: {browser: "ALL"})
  options.send(:binary=, chrome_binary) if chrome_binary
  # @lat: [[system-spec-chromedriver-port-collision#Why the block is 10 wide, not 1]]
  chromedriver_port = 9515 + (ENV["TEST_ENV_NUMBER"].to_i * 10)
  service =
    if chromedriver_binary
      Selenium::WebDriver::Service.chrome(path: chromedriver_binary, port: chromedriver_port)
    else
      Selenium::WebDriver::Service.chrome(port: chromedriver_port)
    end

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
    service: service
  )
end

RSpec.configure do |config|
  config.before(:each, type: :system) { driven_by :rack_test }

  config.before(:each, type: :system, js: true) do
    SystemBrowserPreflight.log_status_once

    if SystemBrowserPreflight.required?
      SystemBrowserPreflight.assert_available!
    else
      unless SystemBrowserPreflight.available?
        skip(SystemBrowserPreflight.missing_requirements_message)
      end
    end

    driven_by :selenium_chromium_headless
  end

  config.after(:each, type: :system) do |example|
    if SystemBrowserSessionManager.dead_driver_error?(example.exception)
      SystemBrowserSessionManager.purge_dead_browser_sessions!
    end
  end
end

module SystemBrowserSessionManager
  DEAD_DRIVER_EXCEPTIONS = [
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::EPIPE,
    EOFError,
    IOError,
    Net::ReadTimeout,
    Net::OpenTimeout,
    (Selenium::WebDriver::Error::NoSuchSessionError if defined?(Selenium::WebDriver::Error::NoSuchSessionError)),
    (Selenium::WebDriver::Error::InvalidSessionIdError if defined?(Selenium::WebDriver::Error::InvalidSessionIdError)),
    (Selenium::WebDriver::Error::SessionNotCreatedError if defined?(Selenium::WebDriver::Error::SessionNotCreatedError)),
    (Selenium::WebDriver::Error::NoSuchDriverError if defined?(Selenium::WebDriver::Error::NoSuchDriverError))
  ].compact.freeze

  UNKNOWN_ERROR_MATCHERS = [
    "disconnected",
    "crashed",
    "not reachable"
  ].freeze

  def self.dead_driver_error?(error)
    return false if error.nil?

    return true if DEAD_DRIVER_EXCEPTIONS.any? { |klass| error.is_a?(klass) }

    if error.is_a?(NoMethodError) && error.message.to_s.include?("closed?")
      return true
    end

    if error.is_a?(Selenium::WebDriver::Error::UnknownError) &&
        UNKNOWN_ERROR_MATCHERS.any? { |pattern| error.message.to_s.downcase.include?(pattern) }
      return true
    end

    if error.class.name.to_s.end_with?("NoSuchSessionError")
      return true
    end

    false
  end

  def self.purge_dead_browser_sessions!
    if Capybara.respond_to?(:session_pool, true)
      pool = Capybara.send(:session_pool)
      pool.keys.each do |key|
        session = pool[key]
        next unless session

        driver = session.respond_to?(:driver) ? session.driver : session.instance_variable_get(:@driver)
        begin
          session.quit
        rescue StandardError, ScriptError
          begin
            driver&.quit
          rescue StandardError, ScriptError
            nil
          end
        ensure
          driver&.instance_variable_set(:@browser, nil)
          pool.delete(key)
        end
      end
    end

    Capybara.send(:specified_session=, nil) if Capybara.respond_to?(:specified_session=, true)
  end
end

module ChromeDriverResetGuard
  def reset!
    super
  rescue StandardError, ScriptError => e
    if SystemBrowserSessionManager.dead_driver_error?(e)
      begin
        quit
      rescue StandardError, ScriptError
        nil
      ensure
        @browser = nil
      end
      SystemBrowserSessionManager.purge_dead_browser_sessions!
    else
      raise
    end
  end
end

module SessionResetGuard
  def reset!
    super
  rescue StandardError, ScriptError => e
    if SystemBrowserSessionManager.dead_driver_error?(e)
      begin
        quit
      rescue StandardError, ScriptError
        nil
      end
      SystemBrowserSessionManager.purge_dead_browser_sessions!
    else
      raise
    end
  end
end

module ChromeDriverScreenshotGuard
  def save_screenshot(...)
    super
  rescue StandardError, ScriptError => e
    if SystemBrowserSessionManager.dead_driver_error?(e)
      SystemBrowserSessionManager.purge_dead_browser_sessions!
      nil
    else
      raise
    end
  end
end

Capybara::Selenium::Driver::ChromeDriver.prepend(ChromeDriverResetGuard) if defined?(Capybara::Selenium::Driver::ChromeDriver)
Capybara::Session.prepend(SessionResetGuard) if defined?(Capybara::Session)
Capybara::Selenium::Driver.prepend(ChromeDriverScreenshotGuard) if defined?(Capybara::Selenium::Driver)
