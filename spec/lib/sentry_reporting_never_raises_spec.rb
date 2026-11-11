# frozen_string_literal: true

require "rails_helper"

# @lat: [[sentry-gem-production-only-bug#Why the Sentry gems load outside production too]]
RSpec.describe "reporting an error outside production" do
  it "can name Sentry at all, which is the condition that failed" do
    expect(defined?(Sentry)).to eq("constant")
  end

  # Listed so moving one, or dropping its report, is noticed here.
  it "still reports from every rescue block the bug was found in" do
    call_sites = %w[
      app/jobs/reconcile_user_districts_job.rb
      app/jobs/refresh_legislators_cache_job.rb
      app/jobs/on_deactivated_phone_delete_user_job.rb
      app/controllers/csp_reports_controller.rb
      app/controllers/concerns/authentication.rb
      app/services/github_pr_service.rb
      app/services/database_backup_service.rb
      app/services/concerns/legislator_vote_upserter.rb
    ]

    missing = call_sites.reject { |path| Rails.root.join(path).file? }
    expect(missing).to be_empty,
      "These files moved. Update the list here, and check the new home still " \
      "reports errors: #{missing.join(", ")}"

    silent = call_sites.reject { |path| Rails.root.join(path).read.include?("Sentry.") }
    expect(silent).to be_empty,
      "These no longer report to Sentry. If that is deliberate, drop them from " \
      "the list: #{silent.join(", ")}"
  end

  # No address means no client, the ordinary state of a run started by hand.
  describe "with no client started" do
    # Guarded because Sentry.close on a client that never started raises
    # NoMethodError on nil — the same shape of fault this file is about.
    around do |example|
      already_initialized = Sentry.initialized?
      begin
        Sentry.close if already_initialized
        example.run
      ensure
        load Rails.root.join("config", "initializers", "sentry.rb").to_s if already_initialized
      end
    end

    it "is not reporting, so the examples below mean something" do
      expect(Sentry.initialized?).to be(false)
    end

    it "does nothing rather than raising, for an exception" do
      expect { Sentry.capture_exception(StandardError.new("nobody is listening")) }
        .not_to raise_error
    end

    it "does nothing rather than raising, for a message" do
      expect { Sentry.capture_message("nobody is listening") }.not_to raise_error
    end
  end
end
