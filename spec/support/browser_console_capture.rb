# frozen_string_literal: true

# Print what the browser logged when a :js system spec fails.
# A Capybara failure names what it could not find, never what broke.
module BrowserConsoleCapture
  SEVERITY = {"DEBUG" => 0, "INFO" => 1, "WARNING" => 2, "SEVERE" => 3}.freeze
  DEFAULT_MINIMUM_LEVEL = "WARNING"
  MAX_REPORT_BYTES = 20_000

  module_function

  def minimum_level
    level = ENV.fetch("SWAY_BROWSER_CONSOLE_LEVEL", DEFAULT_MINIMUM_LEVEL).to_s.upcase
    SEVERITY.key?(level) ? level : DEFAULT_MINIMUM_LEVEL
  end

  # @lat: [[browser-console-capture-design#Why the "captures below WARNING" example is the one that matters]]
  def drain(page)
    driver = page.driver
    return [] unless driver.respond_to?(:browser)

    browser = driver.browser
    return [] unless browser.respond_to?(:logs)

    browser.logs.get(:browser).to_a
  rescue Selenium::WebDriver::Error::WebDriverError,
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::EPIPE,
    EOFError,
    Net::ReadTimeout => e
    log_unreadable_console(e)
    []
  rescue NoMethodError => e
    raise unless e.message.include?("closed?")

    log_unreadable_console(e)
    []
  end

  def log_unreadable_console(error)
    Kernel.warn(
      "[browser-console] a browser was present but its console could not be read: " \
      "#{error.class}: #{error.message}. On a failing spec this usually means the capture ran " \
      "after the session was torn down — it must be prepend_after."
    )
  end

  def filter(entries, level: minimum_level)
    floor = SEVERITY.fetch(level)
    entries.select { |entry| SEVERITY.fetch(entry.level.to_s.upcase, 0) >= floor }
  end

  def format(entries)
    report = entries.map { |entry| "  [#{entry.level}] #{entry.message}" }.join("\n")
    return report if report.bytesize <= MAX_REPORT_BYTES

    truncated = report.byteslice(0, MAX_REPORT_BYTES).to_s
    "#{truncated}\n  ... cut short at #{MAX_REPORT_BYTES} bytes of #{report.bytesize}"
  end

  def artifact_name(example)
    example.location.to_s.sub(%r{\A\./}, "").gsub(/[^0-9A-Za-z]+/, "_")
  end
end

RSpec.configure do |config|
  # prepend_after, not append: append runs after Rails closes the session, so
  # the read fails at the wire and reports nothing. Measured 2026-08-10.
  config.prepend_after(:each, type: :system, js: true) do |example|
    entries = BrowserConsoleCapture.filter(BrowserConsoleCapture.drain(page))

    # Drain always, report only on failure — undrained lines would arrive
    # attached to the next failure.
    next if example.exception.nil? || entries.empty?

    report = BrowserConsoleCapture.format(entries)

    RSpec.configuration.reporter.message(
      "[browser-console] #{entries.size} entr#{(entries.size == 1) ? "y" : "ies"} " \
      "at #{BrowserConsoleCapture.minimum_level} or above during #{example.location}\n#{report}"
    )

    screenshot_dir = ENV["SCREENSHOT_DIR"].presence
    next unless screenshot_dir

    path = File.join(screenshot_dir, "#{BrowserConsoleCapture.artifact_name(example)}.console.log")
    File.write(path, "#{example.location}\n\n#{report}\n")
    RSpec.configuration.reporter.message("[browser-console] saved to #{path}")
  end
end
