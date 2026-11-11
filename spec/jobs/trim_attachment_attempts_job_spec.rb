# frozen_string_literal: true

require "rails_helper"

# @lat: [[attachment-attempts#Attachment download attempts#Retention sweep]]
RSpec.describe TrimAttachmentAttemptsJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:baltimore) { create(:sway_locale, :baltimore) }
  let(:bill) { create(:bill, external_id: "TEST-200", sway_locale: baltimore) }
  let(:download_url) { "https://baltimore.legistar1.com/attachments/981.pdf" }

  def create_attempt_entry(bill:, created_at:, outcome: "failed", error: "Faraday::ConnectionFailed: connection refused",
    attachment_id: 981, url: download_url, filename: "testimony_981.pdf")
    entry = PipelineActivityLogEntry.create!(
      event_type: "attachment_download_attempt",
      subject_type: "Bill",
      subject_id: bill.id.to_s,
      severity: "info",
      title: "Attachment download attempt",
      message: "Attachment #{attachment_id} download #{outcome}",
      payload: {
        "bill_id" => bill.id,
        "bill_external_id" => bill.external_id,
        "sway_locale_id" => bill.sway_locale_id,
        "attachment_id" => attachment_id,
        "filename" => filename,
        "url" => url,
        "status" => outcome,
        "outcome" => outcome,
        "error" => error,
        "attempted_at" => created_at.iso8601
      }
    )
    PipelineActivityLogEntry.where(id: entry.id).update_all(created_at: created_at)
    entry
  end

  before do
    allow(PipelineActivityLogger::Transport).to receive(:dispatch)
    allow(SwayLogging).to receive(:info)
    PipelineActivityLogEntry.delete_all
  end

  describe "constants and queue" do
    it "encodes a retention window strictly longer than RetryFailedAttachmentsJob::LOOKBACK_WINDOW" do
      expect(described_class::RETENTION_DAYS).to eq(30)
      expect(described_class::RETENTION_DAYS.days).to be > RetryFailedAttachmentsJob::LOOKBACK_WINDOW
      expect(described_class::BATCH_SIZE).to eq(500)
    end

    it "runs on the background queue" do
      expect(described_class.new.queue_name).to eq("background")
    end
  end

  describe "#perform — retention boundary and isolation" do
    it "deletes attempt rows older than RETENTION_DAYS and preserves rows within the window" do
      freeze_time do
        old_entry = create_attempt_entry(bill: bill, created_at: 31.days.ago)
        boundary_old_entry = create_attempt_entry(bill: bill, created_at: 30.days.ago - 1.second)
        boundary_young_entry = create_attempt_entry(bill: bill, created_at: 30.days.ago + 1.second)
        young_entry = create_attempt_entry(bill: bill, created_at: 5.days.ago)

        expect { described_class.new.perform }
          .to change { PipelineActivityLogEntry.where(event_type: "attachment_download_attempt").count }
          .from(4).to(2)

        expect(PipelineActivityLogEntry.exists?(old_entry.id)).to be(false)
        expect(PipelineActivityLogEntry.exists?(boundary_old_entry.id)).to be(false)
        expect(PipelineActivityLogEntry.exists?(boundary_young_entry.id)).to be(true)
        expect(PipelineActivityLogEntry.exists?(young_entry.id)).to be(true)
      end
    end

    it "does not delete non-attachment_download_attempt log entries even if older than the retention window" do
      non_attempt_entry = PipelineActivityLogEntry.create!(
        event_type: "state_transition",
        subject_type: "LegislationPipelineRun",
        subject_id: "1",
        severity: "info",
        title: "Stage transition",
        message: "Transitioned",
        payload: {}
      )
      PipelineActivityLogEntry.where(id: non_attempt_entry.id).update_all(created_at: 40.days.ago)

      old_attempt = create_attempt_entry(bill: bill, created_at: 40.days.ago)

      expect { described_class.new.perform }
        .to change { PipelineActivityLogEntry.count }.from(2).to(1)

      expect(PipelineActivityLogEntry.exists?(old_attempt.id)).to be(false)
      expect(PipelineActivityLogEntry.exists?(non_attempt_entry.id)).to be(true)
    end

    it "returns the total integer count of deleted rows and logs completion" do
      freeze_time do
        3.times { |i| create_attempt_entry(bill: bill, created_at: (35 + i).days.ago, attachment_id: 10 + i) }

        deleted_count = described_class.new.perform
        expect(deleted_count).to eq(3)
        expect(SwayLogging).to have_received(:info).with(
          /\[TrimAttachmentAttemptsJob\] complete deleted=3 retention_days=30 cutoff_at=/
        )
      end
    end

    it "returns zero and completes without error when no matching rows exist" do
      expect(described_class.new.perform).to eq(0)
    end
  end

  describe "#perform — multi-batch deletion" do
    it "sweeps more than one batch in a single perform execution when rows exceed BATCH_SIZE" do
      stub_const("#{described_class}::BATCH_SIZE", 2)
      5.times { |i| create_attempt_entry(bill: bill, created_at: (35 + i).days.ago, attachment_id: 100 + i) }
      recent_entry = create_attempt_entry(bill: bill, created_at: 2.days.ago, attachment_id: 999)

      expect { described_class.new.perform }
        .to change { PipelineActivityLogEntry.where(event_type: "attachment_download_attempt").count }
        .from(6).to(1)

      expect(PipelineActivityLogEntry.pluck(:id)).to eq([recent_entry.id])
    end
  end

  describe "#perform — RetryFailedAttachmentsJob invariant preservation" do
    it "strictly preserves attempt rows that RetryFailedAttachmentsJob would select for retry" do
      bill.create_bill_llm_provisioning!(
        testimony_attachments: [
          {
            "filename" => "testimony_981.pdf",
            "attachment_id" => "981",
            "download_status" => "failed",
            "extraction_status" => "skipped",
            "error" => "Faraday::ConnectionFailed: connection refused"
          }
        ]
      )

      retry_eligible = create_attempt_entry(
        bill: bill,
        attachment_id: 981,
        outcome: "failed",
        error: "Faraday::ConnectionFailed: connection refused",
        created_at: 13.days.ago
      )

      stale_attempt = create_attempt_entry(
        bill: bill,
        attachment_id: 982,
        outcome: "failed",
        error: "Faraday::ConnectionFailed: connection refused",
        created_at: 40.days.ago
      )

      retry_job = RetryFailedAttachmentsJob.new
      initial_candidates = retry_job.send(:select_retry_candidates)
      expect(initial_candidates.map { |c| c[:attachment_id].to_s }).to include("981")

      described_class.new.perform

      expect(PipelineActivityLogEntry.exists?(stale_attempt.id)).to be(false)
      expect(PipelineActivityLogEntry.exists?(retry_eligible.id)).to be(true)

      candidates_after_cleanup = retry_job.send(:select_retry_candidates)
      expect(candidates_after_cleanup.map { |c| c[:attachment_id].to_s }).to include("981")
    end

    it "strictly preserves all attempt rows throughout the full 14-day retry lookback window" do
      entry_25h = create_attempt_entry(bill: bill, created_at: 25.hours.ago, attachment_id: 1)
      entry_7d = create_attempt_entry(bill: bill, created_at: 7.days.ago, attachment_id: 2)
      entry_13d = create_attempt_entry(bill: bill, created_at: 13.days.ago + 1.hour, attachment_id: 3)

      expect { described_class.new.perform }.not_to change { PipelineActivityLogEntry.count }

      expect(PipelineActivityLogEntry.where(id: [entry_25h.id, entry_7d.id, entry_13d.id]).count).to eq(3)
    end
  end

  describe "recurring.yml schedule registration" do
    let(:recurring_config) { YAML.load_file(Rails.root.join("config", "recurring.yml")) }

    %w[development production].each do |env|
      it "registers trim_attachment_attempts under #{env}: on the background queue with a Fugit-parseable cron schedule" do
        require "fugit"
        entry = recurring_config[env]["trim_attachment_attempts"]
        expect(entry).to be_present, "expected #{env}: block to include trim_attachment_attempts"
        expect(entry["class"]).to eq(described_class.name)
        expect(entry["queue"]).to eq("background")
        expect(entry).to have_key("schedule")
        expect(entry).not_to have_key("cron")

        parsed = Fugit.parse(entry["schedule"])
        expect(parsed).to be_a(Fugit::Cron)
        expect(parsed.next_time).to be_present
      end
    end

    it "survives solid_queue's has_key?(:schedule) registration filter in development and production" do
      symbolized = ActiveSupport::ConfigurationFile
        .parse(Rails.root.join("config", "recurring.yml"))
        .deep_symbolize_keys

      %i[development production].each do |env|
        registered = symbolized[env]
          .select { |_id, options| options.is_a?(Hash) && options.key?(:schedule) }
          .values
          .map { |options| options[:class] }

        expect(registered).to include(described_class.name),
          "expected #{env}: to register #{described_class.name}"
      end
    end
  end
end
