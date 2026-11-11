# frozen_string_literal: true

require "rails_helper"

# @lat: [[pipeline-activity-log-cleanup-delete-all-callback-skip#Why the job's retention rule excludes rows by both subject_type and subject_id]]
RSpec.describe PipelineActivityLogCleanupJob do
  # Build a PipelineActivityLogEntry with a back-dated `created_at`. The model's
  # after_commit hook would broadcast over ActionCable, which has nothing to do
  # with retention, so the transport hook is stubbed out.
  def create_entry(created_at:, subject_type: nil, subject_id: nil, event_type: "state_transition",
    severity: "info", title: "test", message: "test")
    entry = PipelineActivityLogEntry.new(
      event_type: event_type,
      severity: severity,
      title: title,
      message: message,
      subject_type: subject_type,
      subject_id: subject_id,
      payload: {} #: Hash[Symbol, untyped]
    )
    entry.save!
    # Back-date after saving, so validations and before_create defaults do not overwrite it.
    PipelineActivityLogEntry.where(id: entry.id).update_all(created_at: created_at)
    entry
  end

  before do
    # @lat: [[activity-log-flash-transport#Why the dispatch lives outside the logger]]
    allow(PipelineActivityLogger::Transport).to receive(:dispatch)
    PipelineActivityLogEntry.delete_all
    LegislationPipelineRun.delete_all
  end

  describe "#perform" do
    it "respects the 30-day cutoff: deletes rows older than 30 days, keeps rows newer" do
      # 5 recent (10 days ago) and 5 old (40 days ago), none of them about a run.
      5.times { create_entry(created_at: 10.days.ago) }
      5.times { create_entry(created_at: 40.days.ago) }

      expect { described_class.new.perform }.to change { PipelineActivityLogEntry.count }.from(10).to(5)
      expect(PipelineActivityLogEntry.where("created_at < ?", 30.days.ago).count).to eq(0)
    end

    it "preserves a stale entry linked to the single most-recent LegislationPipelineRun (last-50 rule)" do
      run = create(:legislation_pipeline_run, created_at: 1.day.ago)
      create_entry(
        created_at: 40.days.ago,
        subject_type: "LegislationPipelineRun",
        subject_id: run.id.to_s
      )

      expect { described_class.new.perform }.not_to change { PipelineActivityLogEntry.count }
      expect(PipelineActivityLogEntry.count).to eq(1)
    end

    it "deletes stale entries linked to the OLDEST 10 of 60 LegislationPipelineRun rows; keeps the 50 most recent" do
      # 60 runs, 1 entry each, all entries 40 days old.
      runs = 60.times.map do |i|
        create(
          :legislation_pipeline_run,
          created_at: (60 - i).days.ago # i=0 oldest, i=59 newest
        )
      end
      runs.each do |run|
        create_entry(
          created_at: 40.days.ago,
          subject_type: "LegislationPipelineRun",
          subject_id: run.id.to_s
        )
      end

      expect { described_class.new.perform }.to change { PipelineActivityLogEntry.count }.from(60).to(50)

      preserved_run_ids = LegislationPipelineRun.order(created_at: :desc).limit(50).pluck(:id)
      remaining_subject_ids = PipelineActivityLogEntry.pluck(:subject_id).map(&:to_i)
      expect(remaining_subject_ids).to match_array(preserved_run_ids)
    end

    it "deletes a stale non-run-subject entry (STRICT: Bill subject gets no exemption)" do
      bill = create(:bill)
      create_entry(
        created_at: 40.days.ago,
        subject_type: "Bill",
        subject_id: bill.id.to_s,
        event_type: "paste_summary_accepted",
        title: "Paste summary accepted"
      )
      # Plus one entry linked to a run, which is kept — proof that the WHERE
      # clause exempts only rows whose subject is a LegislationPipelineRun.
      run = create(:legislation_pipeline_run, created_at: 1.day.ago)
      create_entry(
        created_at: 40.days.ago,
        subject_type: "LegislationPipelineRun",
        subject_id: run.id.to_s
      )

      expect { described_class.new.perform }.to change { PipelineActivityLogEntry.count }.from(2).to(1)

      survivor = PipelineActivityLogEntry.first #: PipelineActivityLogEntry
      expect(survivor.subject_type).to eq("LegislationPipelineRun")
      expect(survivor.subject_id).to eq(run.id.to_s)
    end

    it "returns the integer count of deleted rows" do
      3.times { create_entry(created_at: 40.days.ago) }
      result = described_class.new.perform
      expect(result).to eq(3)
    end

    it "handles the zero-preserved-runs edge case (empty LegislationPipelineRun table) without raising" do
      # With no runs at all, nothing is exempt and every aged row is deleted.
      3.times { create_entry(created_at: 40.days.ago) }
      expect { described_class.new.perform }.to change { PipelineActivityLogEntry.count }.from(3).to(0)
    end
  end

  describe "constants" do
    it "encodes the retention window" do
      expect(described_class::RETENTION_DAYS).to eq(30)
      expect(described_class::RECENT_RUNS_PRESERVED).to eq(50)
    end
  end
end
