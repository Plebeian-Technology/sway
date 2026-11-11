# frozen_string_literal: true

require "rails_helper"

# @lat: [[sentry-error-reporting-lanes#Why spec/config/sentry_initializer_spec.rb requires sentry-ruby/sentry-rails by hand]]
require "sentry-ruby"
require "sentry-rails"

# @lat: [[sentry-error-reporting-lanes#Why the initializer is loaded and run, not just read as a comment]]
RSpec.describe "config/initializers/sentry.rb" do
  # A brand-new Configuration for each example, so one example cannot see
  # another's changes and the gem defaults below really are the gem's.
  let(:config) { Sentry::Configuration.new }

  def load_initializer(env)
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new(env))
    allow(Sentry).to receive(:init).and_yield(config)
    load Rails.root.join("config", "initializers", "sentry.rb").to_s
  end

  describe "under RAILS_ENV=production" do
    before { load_initializer("production") }

    # @lat: [[sentry-error-reporting-lanes#Why spec/config/sentry_initializer_spec.rb requires sentry-ruby/sentry-rails by hand]]
    it "does not capture a Sentry event for every intermediate retry" do
      expect(config.rails.active_job_report_on_retry_error).to be(false)
    end

    # The Pi's budget, which is what the retry setting is being weighed against.
    # Pinned right here so the two get read together.
    it "samples traces and profiles at the Pi-appropriate rate" do
      expect(config.traces_sample_rate).to eq(0.1)
      expect(config.profiles_sample_rate).to eq(0.1)
    end

    it "does not send PII" do
      expect(config.send_default_pii).to be(false)
    end

    it "does not include local variables in stack frames" do
      expect(config.include_local_variables).to be(false)
    end

    it "wires SwayErrorScrubber.call into before_send" do
      event = double("event")
      hint = {exception: StandardError.new("boom")}
      expect(SwayErrorScrubber).to receive(:call).with(event, hint).and_return(event)

      expect(config.before_send).to be_a(Proc)
      expect(config.before_send.call(event, hint)).to eq(event)
    end

    # @lat: [[browser-error-reporting#A trailing newline in a DSN turns reporting off without saying so]]
    it "strips the DSN before Sentry parses it as a URI" do
      saved = ENV.key?("SENTRY_DSN") ? ENV["SENTRY_DSN"] : nil
      begin
        ENV["SENTRY_DSN"] = "https://abc@o0.ingest.sentry.io/1\n"

        load_initializer("production")

        expect(config.dsn.to_s).not_to include("\n")
        expect(config.dsn.to_s).to eq("https://abc@o0.ingest.sentry.io/1")
      ensure
        saved.nil? ? ENV.delete("SENTRY_DSN") : ENV["SENTRY_DSN"] = saved
      end
    end
  end

  # The gem's own default, checked apart from ours, on a Configuration the
  # initializer has never touched. If a later sentry-rails flips it, this fails,
  # and the initializer's explicit `false` can be rethought on evidence rather
  # than on the comment that was wrong the first time.
  it "matches the sentry-rails default, which is false" do
    expect(config.rails.active_job_report_on_retry_error).to be(false)
  end

  # Outside production the question is not the environment but whether there is a
  # collector on this machine — a test run has one, a plain rspec does not.
  describe "outside production" do
    it "initialises nothing when no collector address is set" do
      expect(Sentry).not_to receive(:init)

      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
      with_env("RUSTRAK_DSN" => nil) do
        load Rails.root.join("config", "initializers", "sentry.rb").to_s
      end
    end

    it "initialises against a collector on this machine" do
      expect(Sentry).to receive(:init).and_yield(config)

      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
      with_env("RUSTRAK_DSN" => "http://publicid@rustrak:8080/1") do
        load Rails.root.join("config", "initializers", "sentry.rb").to_s
      end

      expect(config.dsn.to_s).to eq("http://publicid@rustrak:8080/1")
    end

    # The refusal that keeps real testimony on this machine.
    it "refuses an address that is not on this machine" do
      expect(Sentry).not_to receive(:init)

      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))
      with_env("RUSTRAK_DSN" => "http://publicid@errors.example.com/1") do
        load Rails.root.join("config", "initializers", "sentry.rb").to_s
      end
    end
  end
end
