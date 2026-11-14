require "spec_helper"

ENV["RAILS_ENV"] = "test"
puts "RAILS_ENV is #{ENV["RAILS_ENV"]}"

require "active_support/core_ext/object/blank"
require "simplecov"
require "yaml"

# @lat: [[verification-gates#RSpec runtime contracts]]
SimpleCov.command_name "rspec-#{ENV["SWAY_TEST_LANE"].presence || "all"}-worker-#{ENV["TEST_ENV_NUMBER"].presence || 1}"

SimpleCov.start "rails" do
  # @lat: [[verification-gates#Onboarding coverage gate]]
  enable_coverage :branch

  group "Models", "app/models"
  group "Services", "app/services"
  group "Jobs", "app/jobs"
  group "Channels", "app/channels"
  group "Controllers", "app/controllers"
  group "Mailers", "app/mailers"

  # @lat: [[verification-gates#RSpec runtime contracts]]
  cover "{app/models,app/services,app/jobs,app/channels,app/controllers}/**/*.rb"
  # @lat: [[verification-gates#Onboarding coverage gate]]
  cover(*YAML.load_file(File.expand_path("../../config/onboarding_coverage_floor.yml", __FILE__)).keys)

  skip "/app/channels/application_cable/"
end

require_relative "../config/environment"
# Prevent database truncation if the environment is production
if Rails.env.production?
  abort("The Rails environment is running in production mode!")
end
require "rspec/rails"

require "webmock/rspec"
# @lat: [[verification-gates#RSpec runtime contracts]]
require "support/live_llm_gate"
require "inertia_rails/rspec"
require "faker"
require "geocoder"
require "pry"
require "capybara/rails"
require "capybara/rspec"

require "support/capybara_helpers"
require "support/env_helpers"
require "support/factory_bot"
require "support/session_double"
require "support/registered_user_fixtures"
require "support/setup"
require "support/shared_examples/seedable"
require "support/shared_examples/requires_sway_admin"
require "support/shared_examples/requires_organization_admin"
require "support/shared_examples/microsecond_precision_timestamps"
require "support/shared_examples/llm_structured_output_adapter"
require "support/shared_contexts/in_memory_rails_cache"
require "support/system_driver"
# Must follow system_driver: the capture is only ever non-empty because the
# driver registered there asks Chrome to keep a console history.
require "support/browser_console_capture"
require "support/report_application_errors"
require "support/twilio_double"
require "support/vcr"
require "support/virtual_authenticator"
require "support/webauthn_double"
require "support/admin_system_helpers"
require "support/narrow_viewport_helpers"
require "support/page_reload_probe"
require "support/webauthn_system_helpers"
require "support/production_snapshot"
require "support/rate_limit_helpers"
require "support/service_worker_stub"
require "support/api_v1_helpers"
require "support/concurrency_helpers"
require "support/legislation_test_artifacts"
require "support/testimony_spec_helpers"
# @lat: [[partial-reload-poll-lists#A partial reload has to carry the version header]]
require "support/inertia_versioned_reload"
require "support/bill_creator_poll_props"
# A controller that exists only in tests, for inspecting Inertia flash messages. Its
# route is only registered when Rails.env.test? is true.
require "support/inertia_flash_probe_controller"
# Helper for measuring how many tokens a cached prompt prefix takes up. It asks
# Anthropic's count_tokens only when the live-LLM opt-in is on, and otherwise estimates
# from the number of characters.
require "support/cache_prefix_tokenizer"

GOOGLE_MAPS_API_KEY_REGEX = /AIza[A-Za-z0-9_-]{35}/

def redact_google_api_key(_url, body)
  if body.is_a?(String)
    body.gsub(GOOGLE_MAPS_API_KEY_REGEX, "GOOGLE_API_KEY_REDACTED")
  else
    JSON.parse(
      body.to_json.gsub(GOOGLE_MAPS_API_KEY_REGEX, "GOOGLE_API_KEY_REDACTED")
    ).with_indifferent_access
  end
end

# @lat: [[verification-gates#RSpec runtime contracts]]
def truncate_application_tables
  conn = ActiveRecord::Base.connection
  protected_tables = %w[schema_migrations ar_internal_metadata]
  conn.disable_referential_integrity do
    (conn.tables - protected_tables).each do |table|
      conn.execute("DELETE FROM #{conn.quote_table_name(table)}")
    end
  end
end

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

module RequestSpecSessionHelpers
  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Request specs switch the complete authentication identity]]
  def sign_in(user)
    _session_hash[:user_id] = user.id
    _session_hash[:auth_identity] = user.created_at.to_i
  end

  def sign_out(_user = nil)
    _session_hash.delete(:user_id)
  end

  private

  def _session_hash
    @_session_hash ||= begin
      h = {} #: Hash[untyped, untyped]
      session_double =
        instance_double(
          ActionDispatch::Request::Session,
          enabled?: true,
          loaded?: false
        )

      allow(session_double).to receive(:[]) { |key| h[key] }
      allow(session_double).to receive(:[]=) { |key, value| h[key] = value }
      allow(session_double).to receive(:delete) { |key| h.delete(key) }
      allow(session_double).to receive(:clear) { h.clear }
      allow(session_double).to receive(:fetch) { |key| h.fetch(key) }
      allow(session_double).to receive(:key?) { |key| h.key?(key) }
      allow(session_double).to receive(:to_hash) { h }
      allow(session_double).to receive(:to_h) { h }
      allow(session_double).to receive(:dig) do |*keys|
        keys.reduce(h) do |hash, key|
          next nil unless hash.is_a?(Hash)
          hash[key] || hash[key.to_s] || (key.is_a?(String) ? hash[key.to_sym] : nil)
        end
      end

      allow_any_instance_of(ActionDispatch::Request).to receive(:session).and_return(session_double)

      h
    end
  end
end

RSpec.configure do |config|
  config.include FactoryBot::Syntax::Methods
  config.include CapybaraHelpers, type: :system
  config.include CapybaraHelpers, type: :feature
  config.include RequestSpecSessionHelpers, type: :request
  Capybara.default_max_wait_time = CapybaraHelpers::SECONDS_TO_WAIT
  config.fixture_paths = [Rails.root.join("spec", "fixtures", "fixtures")]

  config.use_transactional_fixtures = true

  config.infer_spec_type_from_file_location!

  config.filter_rails_from_backtrace!

  config.infer_spec_type_from_file_location!

  config.before(:suite) do
    if (screenshot_dir = ENV["SCREENSHOT_DIR"]) && !screenshot_dir.empty?
      FileUtils.mkdir_p(screenshot_dir)
      FileUtils.rm_rf(Dir.glob("#{screenshot_dir}/*"))
    end

    # Start from an empty database. A run that crashed earlier can leave rows behind
    # that clash with a unique index the next time the suite runs — sway_locales'
    # city/state/country index, for one. Wiping everything up front means what happened
    # in past runs cannot matter.
    truncate_application_tables
  end

  # @lat: [[verification-gates#RSpec runtime contracts]]
  config.prepend_before(:each, type: :system) { self.use_transactional_tests = false }
  config.append_after(:each, type: :system) { truncate_application_tables }

  # Stop one example's CurrentAttributes from bleeding into the next.
  # ActiveSupport::CurrentAttributes clears itself between real web requests, but not
  # between RSpec examples, so clear it by hand.
  config.before do
    Current.reset
    Pipeline::Current.reset
    ActionMailer::Base.deliveries.clear
    NewsArticleRobotsPolicy.reset_cache! if defined?(NewsArticleRobotsPolicy)
  end

  # Ensure non-production test routes (such as /download) remain loaded if previous
  # specs reloaded routes under an alternate environment.
  config.before(:each, type: :request) do
    Rails.application.reload_routes! unless Rails.application.routes.url_helpers.respond_to?(:mobile_download_path)
  end

  config.after do
    Sway::Settings.reset!
    NewsArticleRobotsPolicy.reset_cache! if defined?(NewsArticleRobotsPolicy)
  end

  # @lat: [[verification-gates#RSpec runtime contracts]]
  config.around do |example|
    original_admin_phones = User::ADMIN_PHONES.freeze
    original_api_user_phones = User::API_USER_PHONES.freeze

    begin
      example.run
    ensure
      if !User::ADMIN_PHONES.equal?(original_admin_phones) || !User::ADMIN_PHONES.frozen?
        User.send(:remove_const, :ADMIN_PHONES)
        User.const_set(:ADMIN_PHONES, original_admin_phones)
      end
      if !User::API_USER_PHONES.equal?(original_api_user_phones) || !User::API_USER_PHONES.frozen?
        User.send(:remove_const, :API_USER_PHONES)
        User.const_set(:API_USER_PHONES, original_api_user_phones)
      end
    end
  end

  # Capybara and Selenium were opening the browser at a phone-sized window. That turned
  # up while watching the menu options in the 'navigating the app via the header'
  # scenario in spec/features/project_spec.rb
  # https://stackoverflow.com/a/26977863/6410635
  config.before(:each, type: :system, js: true) do
    page.driver.browser.manage.window.maximize
  rescue StandardError, ScriptError => e
    if defined?(SystemBrowserSessionManager) && SystemBrowserSessionManager.dead_driver_error?(e)
      SystemBrowserSessionManager.purge_dead_browser_sessions!
      page.driver.browser.manage.window.maximize
    else
      raise
    end
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
        "coordinates" => [39.29105, -76.61069],
        "street" => "100 N Holliday St",
        "address" => "Baltimore, MD, USA",
        "postal_code" => "21202",
        "city" => "Baltimore",
        "state" => "Maryland",
        "region_code" => "MD",
        "country" => "United States",
        "country_code" => "US"
      }
    ]
  )
end

Capybara.register_driver :selenium_chrome_headless do |app|
  Capybara::Selenium::Driver.load_selenium
  browser_options =
    Selenium::WebDriver::Chrome::Options.new.tap do |opts|
      opts.add_argument("--headless=new")
      opts.add_argument("--no-sandbox")
      opts.add_argument("--disable-site-isolation-trials")
      opts.add_argument("--window-size=3000,5000")
      opts.add_argument("--verbose")
      opts.add_argument("--disable-gpu") if Gem.win_platform?
      opts.add_argument("--disable-dev-shm-usage")
      opts.add_argument("--disable-infobars")
      opts.add_argument("--disable-notifications")
    end
  Capybara::Selenium::Driver.new(
    app,
    browser: :chrome,
    options: browser_options,
    clear_local_storage: true,
    clear_session_storage: true
  )
end

# Without this Capybara cannot find React elements such as inputs
Capybara.ignore_hidden_elements = false

Capybara.configure do |config|
  config.default_driver = :rack_test
  config.javascript_driver = :selenium_chromium_headless
  # @lat: [[verification-gates#RSpec runtime contracts]]
  config.server = :puma, {Silent: true, config_files: ["-"]}
  # server_port is deliberately NOT set — do not pin it again.
  # @lat: [[verification-gates#RSpec runtime contracts]]
end
