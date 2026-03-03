module CapybaraHelpers
  SCREENSHOT_DIR = ENV["SCREENSHOT_DIR"]
  # Many of our JS feature specs depend on async React updates + network stubs.
  # A slightly longer default reduces flakiness on slower CI/containers.
  SECONDS_TO_WAIT = Integer(ENV.fetch("CAPYBARA_SECONDS_TO_WAIT", "20"))

  def reset_browser_state
    Capybara.reset_sessions!
    clear_browser_storage
  end

  def clear_browser_storage
    # In JS/system specs the browser instance may be reused across scenarios,
    # and app state can be persisted in storage. Clear it to avoid flaky tests.
    visit("about:blank")
    page.execute_script("window.localStorage && window.localStorage.clear();")
    page.execute_script(
      "window.sessionStorage && window.sessionStorage.clear();",
    )
  rescue StandardError
    # no-op: some drivers/environments may not support browser storage
  end

  def wait_until_loaded
    expect(page).to have_no_css("#nprogress", wait: SECONDS_TO_WAIT)
  end

  # https://stackoverflow.com/a/23555725/6410635
  def wait_until(delay = 0.1)
    page.document.synchronize do
      seconds_waited = 0.0
      delay_seconds = delay
      while !yield && seconds_waited < SECONDS_TO_WAIT
        sleep(delay_seconds)
        seconds_waited += delay_seconds
      end

      unless yield
        if SCREENSHOT_DIR.present?
          now = Time.zone.now.to_f.to_s.delete(".")
          FileUtils.mkdir_p(SCREENSHOT_DIR)
          page.save_page("#{SCREENSHOT_DIR}/#{now}.html") # rubocop:disable Lint/Debugger

          # Take screenshot of whole page - https://stackoverflow.com/a/54263355/6410635
          # Selenium Chrome does NOT support the full_page: true option passed to save_screenshot
          window = page.driver.browser.manage.window
          widths = [320, 1400] # leave normal w as last
          widths.each do |w|
            window.resize_to(w, 5000)
            total_width =
              page.driver.execute_script("return document.body.offsetWidth")
            total_height =
              page.driver.execute_script("return document.body.scrollHeight")
            window.resize_to(total_width, total_height)
            page.save_screenshot("#{SCREENSHOT_DIR}/#{now}.png") # rubocop:disable Lint/Debugger
            Rails.logger.info "Saved capybara screenshot to #{SCREENSHOT_DIR}/#{now}.png"
          end
          Kernel.puts "Saved capybara log to #{SCREENSHOT_DIR.gsub("/app/", "")}/#{now}.html and #{SCREENSHOT_DIR.gsub("/app/", "")}/#{now}.png"
        end
        Kernel.raise "Waited for #{SECONDS_TO_WAIT} seconds but condition did not become true"
      end
    end
  end

  def wait_for(selector, **options, &block)
    element = nil
    wait_until do
      element =
        (
          if selector.blank?
            page.find_field(**options)
          else
            page.find(selector, **options)
          end
        )
      block ? yield(element) : element.present?
    rescue Capybara::ElementNotFound
      false
    end
    expect(element).to_not be_nil
    element
  end
end
