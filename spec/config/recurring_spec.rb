# frozen_string_literal: true

require "rails_helper"
require "yaml"

RSpec.describe "config/recurring.yml" do
  let(:config) { YAML.load_file(Rails.root.join("config", "recurring.yml")) }

  # @lat: [[recurring-yml-registration-checks#Why every entry is checked against solid_queue's own registration rule]]
  describe "every entry registers with solid_queue" do
    %w[development production].each do |env|
      describe env do
        it "keys every entry with schedule:, never cron:" do
          config[env].each do |key, entry|
            expect(entry).to have_key("schedule"),
              "#{env}/#{key} has no schedule: key — solid_queue will silently drop it"
            expect(entry).not_to have_key("cron"),
              "#{env}/#{key} uses cron: — solid_queue has no cron: key"
          end
        end

        it "parses every schedule via Fugit and resolves every job class" do
          require "fugit"
          config[env].each do |key, entry|
            parsed = Fugit.parse(entry["schedule"])
            expect(parsed).not_to be_nil,
              "#{env}/#{key} schedule #{entry["schedule"].inspect} is not Fugit-parseable"
            expect(parsed.next_time).to be_present,
              "#{env}/#{key} schedule #{entry["schedule"].inspect} yields no next occurrence"
            klass = entry["class"].constantize
            expect(klass).to be <= ActiveJob::Base,
              "#{env}/#{key} class #{entry["class"]} is not an ActiveJob"
          end
        end
      end
    end
  end

  it "registers legislator_vote_sweep under production:" do
    expect(config["production"]).to include("legislator_vote_sweep")
    entry = config["production"]["legislator_vote_sweep"]
    expect(entry["class"]).to eq("LegislatorVoteSweepJob")
    expect(entry["queue"]).to eq("background")
    expect(entry["schedule"]).to eq("0 9 * * *")
  end

  it "does NOT register the sweep under development:" do
    dev = config["development"] || {}
    expect(dev).not_to include("legislator_vote_sweep")
  end

  # Watches Litestream's continuous copy of the primary database.
  it "registers replication_lag_check under production: on the background queue" do
    expect(config["production"]).to include("replication_lag_check")
    entry = config["production"]["replication_lag_check"]
    expect(entry["class"]).to eq("ReplicationLagCheckJob")
    expect(entry["queue"]).to eq("background")
    expect(entry["schedule"]).to eq("*/15 * * * *")
  end

  it "does NOT register replication_lag_check under development:" do
    dev = config["development"] || {}
    expect(dev).not_to include("replication_lag_check")
  end

  # @lat: [[legislation-artifact-backup#Why the sweep runs daily rather than as often as the database backup]]
  it "registers backup_legislation_artifacts under production: on the background queue" do
    expect(config["production"]).to include("backup_legislation_artifacts")
    entry = config["production"]["backup_legislation_artifacts"]
    expect(entry["class"]).to eq("BackupLegislationArtifactsJob")
    expect(entry["queue"]).to eq("background")
    expect(entry["schedule"]).to eq("0 7 * * *")
  end

  it "does NOT register backup_legislation_artifacts under development:" do
    dev = config["development"] || {}
    expect(dev).not_to include("backup_legislation_artifacts")
  end

  # @lat: [[scheduled-job-monitoring#Why a job that sends real messages is scheduled in production only]]
  it "registers voting_reminder under production: on the default queue" do
    expect(config["production"]).to include("voting_reminder")
    entry = config["production"]["voting_reminder"]
    expect(entry["class"]).to eq("VotingReminderJob")
    expect(entry["queue"]).to eq("default")
    expect(entry["schedule"]).to eq("0 16 * * *")
  end

  it "does NOT register voting_reminder under development:" do
    dev = config["development"] || {}
    expect(dev).not_to include("voting_reminder")
  end

  # Writes the caching instruction onto audio an admin uploaded
  # straight to the bucket, which the server never sees.
  it "registers audio_cache_control under production: on the background queue" do
    expect(config["production"]).to include("audio_cache_control")
    entry = config["production"]["audio_cache_control"]
    expect(entry["class"]).to eq("AudioCacheControlJob")
    expect(entry["queue"]).to eq("background")
    expect(entry["schedule"]).to eq("30 5 * * 0")
  end

  # A developer machine has no service-account key for the bucket, so the pass
  # would raise there every week.
  it "does NOT register audio_cache_control under development:" do
    dev = config["development"] || {}
    expect(dev).not_to include("audio_cache_control")
  end

  it "does not use the natural-language 'EST' string (RESEARCH Pitfall 8)" do
    entry = config["production"]["legislator_vote_sweep"]
    schedule = entry["schedule"] || ""
    expect(schedule).not_to match(/EST/i)
  end

  it "keeps the UTC-fixed, drift-accepted decision reachable from the file" do
    section = "scheduled-job-monitoring#Scheduled job monitoring#Every entry names schedule, and every schedule is a UTC cron string"
    raw = Rails.root.join("config", "recurring.yml").read
    expect(raw).to include("@lat: [[#{section}]]"),
      "config/recurring.yml no longer points at the section that carries the schedule conventions"

    explanation = Rails.root.join("lat.md", "explanation", "scheduled-job-monitoring.md").read
    expect(explanation).to match(/fixed to UTC/i),
      "the section no longer says the schedule hour is fixed to UTC"
    expect(explanation).to match(/daylight-saving drift/i),
      "the section no longer says the accepted cost of a fixed UTC hour is daylight-saving drift"
  end

  # The retention sweep over the queue database has to be scheduled in both
  # environments.
  describe "solid_queue_retention" do
    %w[development production].each do |env|
      it "is registered under #{env}: with a Fugit-parseable cron schedule" do
        require "fugit"
        entry = config[env]["solid_queue_retention"]
        expect(entry).to be_present
        expect(entry["class"]).to eq("SolidQueueRetentionJob")
        expect(entry["queue"]).to eq("background")
        expect(Fugit.parse(entry["schedule"])).to be_a(Fugit::Cron)
      end
    end
  end

  # @lat: [[bill-interesting-score#Why retention keeps the newest row for each bill]]
  describe "bill_interesting_score_retention" do
    %w[development production].each do |env|
      it "is registered under #{env}: with a Fugit-parseable cron schedule" do
        require "fugit"
        entry = config[env]["bill_interesting_score_retention"]
        expect(entry).to be_present
        expect(entry["class"]).to eq("BillInterestingScoreRetentionJob")
        expect(entry["queue"]).to eq("background")
        expect(Fugit.parse(entry["schedule"])).to be_a(Fugit::Cron)
      end
    end
  end

  # @lat: [[attachment-attempts#Attachment download attempts#Retention sweep]]
  describe "trim_attachment_attempts" do
    %w[development production].each do |env|
      it "is registered under #{env}: with a Fugit-parseable cron schedule" do
        require "fugit"
        entry = config[env]["trim_attachment_attempts"]
        expect(entry).to be_present
        expect(entry["class"]).to eq("TrimAttachmentAttemptsJob")
        expect(entry["queue"]).to eq("background")
        expect(Fugit.parse(entry["schedule"])).to be_a(Fugit::Cron)
      end
    end
  end

  # @lat: [[recurring-yml-registration-checks#Why specific tasks get their own "is registered" guard, not just the generic checks]]
  describe "reclaim_abandoned_summary_runs (B23-02)" do
    %w[development production].each do |env|
      it "is registered under #{env}: with a Fugit-parseable cron schedule" do
        require "fugit"
        entry = config[env]["reclaim_abandoned_summary_runs"]
        expect(entry).to be_present
        expect(entry["class"]).to eq("ReclaimAbandonedSummaryRunsJob")
        expect(entry["queue"]).to eq("background")
        expect(Fugit.parse(entry["schedule"])).to be_a(Fugit::Cron)
      end
    end
  end

  # @lat: [[recurring-yml-registration-checks#Why specific tasks get their own "is registered" guard, not just the generic checks]]
  describe "reclaim_abandoned_pipeline_runs" do
    %w[development production].each do |env|
      it "is registered under #{env}: with a Fugit-parseable cron schedule" do
        require "fugit"
        entry = config[env]["reclaim_abandoned_pipeline_runs"]
        expect(entry).to be_present
        expect(entry["class"]).to eq("ReclaimAbandonedPipelineRunsJob")
        expect(entry["queue"]).to eq("background")
        expect(Fugit.parse(entry["schedule"])).to be_a(Fugit::Cron)
      end
    end
  end

  # @lat: [[registration-dead-ends#A skipped lookup is recorded so it can be retried#The hourly job assigns what was skipped]]
  describe "assign_pending_representatives" do
    %w[development production].each do |env|
      it "is registered under #{env}: with a Fugit-parseable cron schedule" do
        require "fugit"
        entry = config[env]["assign_pending_representatives"]
        expect(entry).to be_present
        expect(entry["class"]).to eq("AssignPendingRepresentativesJob")
        expect(entry["queue"]).to eq("background")
        expect(entry["schedule"]).to eq("15 * * * *")
        expect(Fugit.parse(entry["schedule"])).to be_a(Fugit::Cron)
      end
    end
  end

  describe "ingest_summary_batches" do
    %w[development production].each do |env|
      it "is registered under #{env}: with a Fugit-parseable cron schedule" do
        require "fugit"
        entry = config[env]["ingest_summary_batches"]
        expect(entry).to be_present
        expect(entry["class"]).to eq("IngestSummaryBatchesJob")
        expect(entry["queue"]).to eq("background")
        expect(Fugit.parse(entry["schedule"])).to be_a(Fugit::Cron)
      end
    end
  end

  # @lat: [[recurring-yml-registration-checks#Why every entry is checked against solid_queue's own registration rule]]
  describe "daily/weekly org digest jobs (CR-01)" do
    {
      "daily_org_digest_job" => "DailyOrgDigestJob",
      "weekly_org_digest_job" => "WeeklyOrgDigestJob"
    }.each do |task_id, class_name|
      %w[development production].each do |env|
        it "registers #{task_id} under #{env}: with a schedule: key, not cron:" do
          entry = config[env][task_id]
          expect(entry).to be_present
          expect(entry["class"]).to eq(class_name)
          expect(entry["queue"]).to eq("background")
          expect(entry).to have_key("schedule")
          expect(entry).not_to have_key("cron")
        end

        it "uses a Fugit-parseable cron schedule for #{task_id} under #{env}:" do
          require "fugit"
          schedule = config[env][task_id]["schedule"]
          expect(Fugit.parse(schedule)).to be_a(Fugit::Cron)
        end
      end
    end

    # @lat: [[recurring-yml-registration-checks#Why every entry is checked against solid_queue's own registration rule]]
    it "survives solid_queue's has_key?(:schedule) registration filter" do
      symbolized = ActiveSupport::ConfigurationFile
        .parse(Rails.root.join("config", "recurring.yml"))
        .deep_symbolize_keys

      %i[development production].each do |env|
        registered = symbolized[env]
          .select { |_id, options| options.is_a?(Hash) && options.key?(:schedule) }
          .values
          .map { |options| options[:class] }

        expect(registered).to include("DailyOrgDigestJob", "WeeklyOrgDigestJob"),
          "expected #{env}: digest jobs to register, got: #{registered.inspect}"
      end
    end
  end

  describe "notify_bill_of_the_month_users_job" do
    %w[development production].each do |env|
      it "registers notify_bill_of_the_month_users_job under #{env}:" do
        expect(config[env]).to include("notify_bill_of_the_month_users_job")
        entry = config[env]["notify_bill_of_the_month_users_job"]
        expect(entry["class"]).to eq("NotifyBillOfTheMonthUsersJob")
        expect(entry["queue"]).to eq("background")
        expect(entry["schedule"]).to eq("every day at 6pm")
      end
    end
  end
end
