# frozen_string_literal: true

module VirtualAuthenticator
  def enable_virtual_authenticator
    browser = page.driver.browser

    execute_cdp(browser, "WebAuthn.enable")
    execute_cdp(
      browser,
      "WebAuthn.addVirtualAuthenticator",
      {
        options: {
          protocol: "ctap2",
          transport: "internal",
          hasResidentKey: true,
          hasUserVerification: true,
          isUserVerified: true,
          automaticPresenceSimulation: true,
        },
      },
    ).fetch("authenticatorId")
  rescue Selenium::WebDriver::Error::WebDriverError, Selenium::WebDriver::Error::NoSuchDriverError => e
    skip("Virtual authenticator unavailable in this environment: #{e.message}")
  end

  def disable_virtual_authenticator(authenticator_id)
    browser = page.driver.browser

    begin
      execute_cdp(
        browser,
        "WebAuthn.removeVirtualAuthenticator",
        {
          authenticatorId: authenticator_id,
        },
      )
    rescue StandardError
      nil
    ensure
      execute_cdp(browser, "WebAuthn.disable")
    end
  rescue StandardError
    nil
  end

  private

  def execute_cdp(browser, command, params = nil)
    browser.execute_cdp(command, **(params || {}))
  end
end

RSpec.configure do |config|
  config.include VirtualAuthenticator, type: :system
end
