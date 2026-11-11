# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Browser worker crash recovery", type: :system, js: true do
  describe "recovering from a dead ChromeDriver in the same worker process" do
    it "runs an initial example successfully" do
      visit root_path
      expect(page).to have_button("Continue with Phone", wait: 10)
    end

    it "encounters a dead driver error when ChromeDriver terminates mid-execution" do
      visit root_path
      expect(page).to have_button("Continue with Phone", wait: 10)

      service_manager = page.driver.browser.instance_variable_get(:@service_manager)
      if service_manager.respond_to?(:stop)
        service_manager.stop
      else
        bridge = page.driver.browser.instance_variable_get(:@bridge)
        pid = bridge&.instance_variable_get(:@service)&.instance_variable_get(:@process)&.pid
        Process.kill("KILL", pid) if pid
      end

      # Attempt a browser command on the dead ChromeDriver connection
      expect {
        page.execute_script("window.location.reload()")
      }.to raise_error { |error|
        expect(SystemBrowserSessionManager.dead_driver_error?(error)).to be true
      }
    end

    it "allows a subsequent unrelated example in the same worker to acquire a fresh browser and pass" do
      visit root_path
      expect(page).to have_button("Continue with Phone", wait: 10)
    end

    it "allows further subsequent examples in the same worker to continue passing" do
      visit root_path
      expect(page).to have_button("Continue with Phone", wait: 10)
    end
  end

  describe "recovering when window maximize encounters a dead browser in before hook" do
    it "recovers from a dead driver before maximize" do
      visit root_path
      expect(page).to have_button("Continue with Phone", wait: 10)

      # Stop the service manager so the existing browser is dead
      service_manager = page.driver.browser.instance_variable_get(:@service_manager)
      service_manager&.stop

      # Verify that maximizing or executing now triggers recovery via SystemBrowserSessionManager
      expect do
        page.driver.browser.manage.window.maximize
      rescue StandardError, ScriptError => e
        if SystemBrowserSessionManager.dead_driver_error?(e)
          SystemBrowserSessionManager.purge_dead_browser_sessions!
          page.driver.browser.manage.window.maximize
        else
          raise
        end
      end.not_to raise_error

      visit root_path
      expect(page).to have_button("Continue with Phone", wait: 10)
    end
  end

  describe "SystemBrowserSessionManager error classification" do
    it "identifies network connection errors as dead driver errors" do
      expect(SystemBrowserSessionManager.dead_driver_error?(Errno::ECONNREFUSED.new)).to be true
      expect(SystemBrowserSessionManager.dead_driver_error?(Errno::ECONNRESET.new)).to be true
      expect(SystemBrowserSessionManager.dead_driver_error?(Errno::EPIPE.new)).to be true
      expect(SystemBrowserSessionManager.dead_driver_error?(EOFError.new)).to be true
      expect(SystemBrowserSessionManager.dead_driver_error?(Net::ReadTimeout.new)).to be true
    end

    it "identifies NoMethodError matching closed? as dead driver errors" do
      closed_socket_error = NoMethodError.new("undefined method 'closed?' for nil")
      other_nomethod_error = NoMethodError.new("undefined method 'foo' for nil")

      expect(SystemBrowserSessionManager.dead_driver_error?(closed_socket_error)).to be true
      expect(SystemBrowserSessionManager.dead_driver_error?(other_nomethod_error)).to be false
    end

    it "identifies unknown errors matching disconnected or crashed" do
      disconnected_error = Selenium::WebDriver::Error::UnknownError.new("disconnected: not connected to DevTools")
      crashed_error = Selenium::WebDriver::Error::UnknownError.new("tab crashed")
      unrelated_error = Selenium::WebDriver::Error::UnknownError.new("unrelated unknown error")

      expect(SystemBrowserSessionManager.dead_driver_error?(disconnected_error)).to be true
      expect(SystemBrowserSessionManager.dead_driver_error?(crashed_error)).to be true
      expect(SystemBrowserSessionManager.dead_driver_error?(unrelated_error)).to be false
    end

    it "returns false for nil or standard application errors" do
      expect(SystemBrowserSessionManager.dead_driver_error?(nil)).to be false
      expect(SystemBrowserSessionManager.dead_driver_error?(StandardError.new("validation failed"))).to be false
    end
  end
end
