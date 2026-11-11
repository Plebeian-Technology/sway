# frozen_string_literal: true

require "rails_helper"

# @lat: [[browser-console-capture-design#Why the "captures below WARNING" example is the one that matters]]
RSpec.describe BrowserConsoleCapture, type: :system do
  describe "reading the console out of a real browser", js: true do
    # Collect across polls: drain empties the buffer, so a plain retry loop
    # would discard the line it is waiting for.
    def drain_until(planted)
      collected = []
      wait_until do
        collected.concat(BrowserConsoleCapture.drain(page))
        collected.any? { |entry| entry.message.to_s.include?(planted) }
      end
      collected
    end

    it "hands back a message the page wrote to its console" do
      planted = "planted-console-error-#{SecureRandom.hex(4)}"

      visit root_path
      expect(page).to have_button("Continue with Phone", wait: 10)

      page.execute_script("console.error(#{planted.to_json})")

      entries = drain_until(planted)
      matching = entries.select { |entry| entry.message.to_s.include?(planted) }

      expect(matching).not_to be_empty
      expect(matching.first.level.to_s.upcase).to eq("SEVERE")
    end

    it "captures below WARNING, which is the only thing logging_prefs buys" do
      planted = "planted-console-debug-#{SecureRandom.hex(4)}"

      visit root_path
      expect(page).to have_button("Continue with Phone", wait: 10)

      # debug, not error: chromedriver returns WARNING+ either way.
      page.execute_script("console.debug(#{planted.to_json})")

      entries = drain_until(planted)
      matching = entries.select { |entry| entry.message.to_s.include?(planted) }

      expect(matching).not_to be_empty,
        "No DEBUG entry holding #{planted.inspect}. Check that spec/support/system_driver.rb " \
        "still passes logging_prefs: {browser: \"ALL\"} — without it Chrome reports WARNING+ only."
      expect(matching.first.level.to_s.upcase).to eq("DEBUG")
    end

    it "captures an uncaught exception, which is the case that motivated it" do
      planted = "planted-uncaught-#{SecureRandom.hex(4)}"

      visit root_path
      expect(page).to have_button("Continue with Phone", wait: 10)

      # From a timer so it escapes execute_script and is genuinely uncaught.
      page.execute_script("setTimeout(function () { throw new Error(#{planted.to_json}); }, 0)")

      entries = drain_until(planted)

      expect(entries.map(&:message).join("\n")).to include(planted)
    end

    it "empties the buffer as it reads, so one example cannot report against the next" do
      planted = "planted-drain-once-#{SecureRandom.hex(4)}"

      visit root_path
      expect(page).to have_button("Continue with Phone", wait: 10)

      page.execute_script("console.error(#{planted.to_json})")
      drain_until(planted)

      expect(BrowserConsoleCapture.drain(page).map(&:message).join("\n")).not_to include(planted)
    end
  end

  describe "drivers that keep no console" do
    # :rack_test has no browser at all, so this case must stay quiet.
    it "returns nothing instead of raising, and says nothing about it" do
      expect(Kernel).not_to receive(:warn)

      expect(BrowserConsoleCapture.drain(page)).to eq([])
    end
  end

  describe "a browser that is there but cannot answer" do
    # The failure that happened: hook ran after teardown, read failed, and
    # nothing was reported on a failing spec.
    # Plain doubles: selenium mixes HasLogs into the driver INSTANCE, so
    # Selenium::WebDriver::Driver has no #logs for a verifying double to find.
    let(:dead_browser) do
      instance = double("selenium browser")
      allow(instance).to receive(:logs)
        .and_raise(Selenium::WebDriver::Error::WebDriverError, "invalid session id")
      instance
    end

    let(:dead_page) { double("capybara session", driver: double("driver", browser: dead_browser)) }

    it "says out loud that it could not read, instead of returning empty in silence" do
      expect(Kernel).to receive(:warn).with(/console could not be read/)

      expect(described_class.drain(dead_page)).to eq([])
    end

    it "names prepend_after in the warning, because that is the cause worth checking first" do
      allow(Kernel).to receive(:warn)

      described_class.drain(dead_page)

      expect(Kernel).to have_received(:warn).with(/prepend_after/)
    end

    it "handles connection refused when chromedriver has crashed" do
      conn_refused_browser = double("selenium browser")
      allow(conn_refused_browser).to receive(:logs).and_raise(Errno::ECONNREFUSED, "Connection refused")
      conn_refused_page = double("capybara session", driver: double("driver", browser: conn_refused_browser))

      expect(Kernel).to receive(:warn).with(/console could not be read/)
      expect(described_class.drain(conn_refused_page)).to eq([])
    end

    it "handles NoMethodError when net/http socket was closed" do
      nil_socket_browser = double("selenium browser")
      allow(nil_socket_browser).to receive(:logs).and_raise(NoMethodError, "undefined method 'closed?' for nil")
      nil_socket_page = double("capybara session", driver: double("driver", browser: nil_socket_browser))

      expect(Kernel).to receive(:warn).with(/console could not be read/)
      expect(described_class.drain(nil_socket_page)).to eq([])
    end

    it "re-raises NoMethodError when unrelated to closed socket" do
      broken_browser = double("selenium browser")
      allow(broken_browser).to receive(:logs).and_raise(NoMethodError, "undefined method 'foo' for Object")
      broken_page = double("capybara session", driver: double("driver", browser: broken_browser))

      expect do
        described_class.drain(broken_page)
      end.to raise_error(NoMethodError, /undefined method 'foo'/)
    end
  end

  describe "choosing what is worth printing" do
    def entry(level, message)
      Selenium::WebDriver::LogEntry.new(level, 0, message)
    end

    it "keeps warnings and errors and drops the chatter" do
      entries = [
        entry("DEBUG", "debug line"),
        entry("INFO", "info line"),
        entry("WARNING", "warning line"),
        entry("SEVERE", "severe line")
      ]

      kept = described_class.filter(entries, level: "WARNING").map(&:message)

      expect(kept).to eq(["warning line", "severe line"])
    end

    it "keeps everything when asked for DEBUG" do
      entries = [entry("DEBUG", "debug line"), entry("SEVERE", "severe line")]

      expect(described_class.filter(entries, level: "DEBUG").size).to eq(2)
    end

    it "treats a level it does not recognise as the least severe rather than dropping it" do
      # An unknown level is still evidence, so it sorts to the bottom rather
      # than being dropped.
      kept = described_class.filter([entry("UNKNOWN", "odd line")], level: "DEBUG")

      expect(kept.map(&:message)).to eq(["odd line"])
    end

    it "falls back to the default when the environment names a level that does not exist" do
      ENV["SWAY_BROWSER_CONSOLE_LEVEL"] = "LOUD"

      expect(described_class.minimum_level).to eq(BrowserConsoleCapture::DEFAULT_MINIMUM_LEVEL)
    ensure
      ENV.delete("SWAY_BROWSER_CONSOLE_LEVEL")
    end
  end

  describe "keeping the report readable" do
    def entry(level, message)
      Selenium::WebDriver::LogEntry.new(level, 0, message)
    end

    it "cuts a runaway report short and says that it did" do
      huge = entry("SEVERE", "x" * (BrowserConsoleCapture::MAX_REPORT_BYTES * 2))

      report = described_class.format([huge])

      expect(report.bytesize).to be <= BrowserConsoleCapture::MAX_REPORT_BYTES + 100
      expect(report).to include("cut short")
    end

    it "builds a filename that survives being written to disk" do
      example_double = instance_double(RSpec::Core::Example, location: "./spec/system/a_spec.rb:42")

      name = described_class.artifact_name(example_double)

      expect(name).to eq("spec_system_a_spec_rb_42")
      expect(name).not_to include("/")
    end
  end
end
