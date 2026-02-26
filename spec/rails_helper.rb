# This file is copied to spec/ when you run 'rails generate rspec:install'
require "spec_helper"

ENV["RAILS_ENV"] = "test"
puts "RAILS_ENV is #{ENV["RAILS_ENV"]}"

require_relative "../config/environment"
# Prevent database truncation if the environment is production
abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"
# Add additional requires below this line. Rails is not loaded until this point!

require "inertia_rails/rspec"
require "rspec/sorbet"
require "faker"
require "geocoder"
require "simplecov"
require "pry"
require "capybara/rails"
require "capybara/rspec"

require "support/capybara_helpers"
require "support/factory_bot"
require "support/session_double"
require "support/setup"
require "support/system_driver"
require "support/twilio_double"
require "support/virtual_authenticator"
require "support/webauthn_double"

# SimpleCov.start "rails"
SimpleCov.start "rails"

GOOGLE_MAPS_API_KEY_REGEX = /A[A-Za-z0-9_-]{38}/

def redact_google_api_key(_url, body)
  if body.is_a?(String)
    body.gsub(GOOGLE_MAPS_API_KEY_REGEX, "GOOGLE_API_KEY_REDACTED")
  else
    JSON.parse(body.to_json.gsub(GOOGLE_MAPS_API_KEY_REGEX, "GOOGLE_API_KEY_REDACTED")).with_indifferent_access
  end
end

# Requires supporting ruby files with custom matchers and macros, etc, in
# spec/support/ and its subdirectories. Files matching `spec/**/*_spec.rb` are
# run as spec files by default. This means that files in spec/support that end
# in _spec.rb will both be required and run as specs, causing the specs to be
# run twice. It is recommended that you do not name files matching this glob to
# end with _spec.rb. You can configure this pattern with the --pattern
# option on the command line or in ~/.rspec, .rspec or `.rspec-local`.
#
# The following line is provided for convenience purposes. It has the downside
# of increasing the boot-up time by auto-requiring all files in the support
# directory. Alternatively, in the individual `*_spec.rb` files, manually
# require only the support files necessary.
#
# Rails.root.glob('spec/support/**/*.rb').sort.each { |f| require f }

# Checks for pending migrations and applies them before tests are run.
# If you are not using ActiveRecord, you can remove these lines.
begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include FactoryBot::Syntax::Methods
  # Remove this line if you're not using ActiveRecord or ActiveRecord fixtures
  config.fixture_paths = [
    Rails.root.join("spec", "fixtures", "fixtures")
  ]

  config.use_transactional_fixtures = true

  # The different available types are documented in the features, such as in
  # https://rspec.info/features/6-0/rspec-rails
  config.infer_spec_type_from_file_location!

  # Filter lines from Rails gems in backtraces.
  config.filter_rails_from_backtrace!
  # arbitrary gems may also be filtered via:
  # config.filter_gems_from_backtrace("gem name")

  # The different available types are documented in the features, such as in
  # https://rspec.info/features/6-0/rspec-rails
  config.infer_spec_type_from_file_location!

  config.before(:suite) do
    if ENV["SCREENSHOT_DIR"].present?
      FileUtils.mkdir_p(ENV["SCREENSHOT_DIR"])
      FileUtils.rm_rf(Dir.glob("#{ENV["SCREENSHOT_DIR"]}/*"))
    end
  end

  # Capybara/Selenium was using mobile sizing for some reason.
  # This was determined by viewing the menu options 'navigating the app via the header' scenario in
  # spec/features/project_spec.rb
  # https://stackoverflow.com/a/26977863/6410635
  config.before(:each, type: :system, js: true) do
    page.driver.browser.manage.window.maximize
  end

  config.around(:each, :caching) do |example|
    caching = ActionController::Base.perform_caching
    ActionController::Base.perform_caching = example.metadata[:caching]
    example.run
    Rails.cache.clear
    ActionController::Base.perform_caching = caching
  end

  # https://github.com/alexreisner/geocoder?tab=readme-ov-file#testing
  Geocoder.configure(lookup: :test, ip_lookup: :test)

  Geocoder::Lookup::Test.set_default_stub(
    [
      {
        "coordinates" => [39.29221443827911, -76.57607705974378],
        "street" => "2901 E Baltimore St",
        "address" => "Baltimore, MD, USA",
        "postal_code" => "21224",
        "city" => "Baltimore",
        "state" => "Maryland",
        "region_code" => "MD",
        "country" => "United States",
        "country_code" => "US",
      },
    ],
  )
end

Capybara.register_driver :selenium_chrome_headless do |app|
  Capybara::Selenium::Driver.load_selenium
  browser_options = Selenium::WebDriver::Chrome::Options.new.tap do |opts|
    opts.add_argument("--headless=new")
    opts.add_argument("--no-sandbox")
    opts.add_argument("--disable-site-isolation-trials")
    opts.add_argument("--window-size=3000,5000")
    opts.add_argument("--verbose")
    opts.add_argument("--disable-gpu") if Gem.win_platform?
    opts.add_argument("--disable-dev-shm-usage")
    opts.add_argument("--disable-infobars")
    opts.add_argument("--disable-notifications")

    # Capture chrome logs for debugging
    # opts.add_argument("--log-net-log=/tmp/chrome-netlog.json")
    # opts.add_argument("--net-log-capture-mode=Everything")
    # opts.add_argument("--enable-logging=stderr")
    # opts.add_argument("--v=1")
  end
  Capybara::Selenium::Driver.new(app, browser: :chrome,
    options: browser_options,
    clear_local_storage: true,
    clear_session_storage: true)
end

# Without this Capybara cannot find React elements such as inputs
Capybara.ignore_hidden_elements = false

Capybara.configure do |config|
  config.default_driver = :rack_test
  config.javascript_driver = :selenium_chromium_headless
  # ViteRuby uses Dir.chdir internally while computing digests/manifest lookups.
  # Running Capybara's Puma server with multiple threads can trigger concurrent
  # `chdir` blocks and raise "conflicting chdir during another chdir block".
  config.server = :puma, { Threads: "0:1", Silent: true }
  config.server_port = (1 << 16) - 2
end
