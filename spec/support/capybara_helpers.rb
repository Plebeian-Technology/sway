module CapybaraHelpers
  SCREENSHOT_DIR = ENV["SCREENSHOT_DIR"]
  # Many of our browser specs wait on React updates that arrive later and on
  # stubbed network calls. A slightly longer default makes them fail less often
  # on slow CI machines and containers.
  SECONDS_TO_WAIT = Integer(ENV.fetch("CAPYBARA_SECONDS_TO_WAIT", "20"))

  def reset_browser_state
    Capybara.reset_sessions!
    clear_browser_storage
  end

  def clear_browser_storage
    # System specs may reuse the same browser across scenarios, and the app
    # keeps state in browser storage. Clearing it stops one test leaking into
    # the next.
    visit("about:blank")
    page.execute_script("window.localStorage && window.localStorage.clear();")
    page.execute_script(
      "window.sessionStorage && window.sessionStorage.clear();"
    )
  rescue
    # Do nothing: some drivers and environments have no browser storage
  end

  # @lat: [[capybara-wait-semantics#Why waiting for an absence can pass instantly]]
  def wait_until_loaded
    expect(page).to have_no_css("#nprogress", wait: SECONDS_TO_WAIT)
  end

  # @lat: [[bills-category-filter#One control, four themes]]
  def open_category_filter
    trigger = find("[data-testid='bills-category-filter']")
    trigger.click unless trigger["aria-expanded"] == "true"
  end

  def toggle_category(name)
    open_category_filter
    find(:checkbox, name).click
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
        if (screenshot_dir = SCREENSHOT_DIR) && screenshot_dir.present?
          now = Time.zone.now.to_f.to_s.delete(".")
          FileUtils.mkdir_p(screenshot_dir)
          page.save_page("#{screenshot_dir}/#{now}.html") # rubocop:disable Lint/Debugger

          # Screenshot the whole page - https://stackoverflow.com/a/54263355/6410635
          # Selenium Chrome ignores the full_page: true option passed to save_screenshot
          window = page.driver.browser.manage.window
          widths = [320, 1400] # keep the normal width last
          widths.each do |w|
            window.resize_to(w, 5000)
            total_width =
              page.driver.execute_script("return document.body.offsetWidth")
            total_height =
              page.driver.execute_script("return document.body.scrollHeight")
            window.resize_to(total_width, total_height)
            page.save_screenshot("#{screenshot_dir}/#{now}.png") # rubocop:disable Lint/Debugger
            Rails.logger.info "Saved capybara screenshot to #{screenshot_dir}/#{now}.png"
          end
          Kernel.puts "Saved capybara log to #{screenshot_dir.gsub("/app/", "")}/#{now}.html and #{screenshot_dir.gsub("/app/", "")}/#{now}.png"
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

RSpec.configure do |config|
  config.around(:each, type: :system) do |example|
    previous_server_host = Capybara.server_host
    previous_app_host = Capybara.app_host
    previous_always_include_port = Capybara.always_include_port

    begin
      Capybara.server_host = "localhost"
      Capybara.app_host = "http://localhost"
      Capybara.always_include_port = true

      example.run
    ensure
      Capybara.server_host = previous_server_host
      Capybara.app_host = previous_app_host
      Capybara.always_include_port = previous_always_include_port
    end
  end
end
