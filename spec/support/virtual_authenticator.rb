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
    ).fetch("authenticatorId").to_s
  rescue Selenium::WebDriver::Error::WebDriverError,
         Selenium::WebDriver::Error::NoSuchDriverError => e
    skip("Virtual authenticator unavailable in this environment: #{e.message}")
  end

  def disable_virtual_authenticator(authenticator_id)
    browser = page.driver.browser

    begin
      execute_cdp(
        browser,
        "WebAuthn.removeVirtualAuthenticator",
        { authenticatorId: authenticator_id },
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
    if params
      browser.execute_cdp(command, **params)
    else
      browser.execute_cdp(command)
    end
  end
end

RSpec.configure { |config| config.include VirtualAuthenticator, type: :system }
