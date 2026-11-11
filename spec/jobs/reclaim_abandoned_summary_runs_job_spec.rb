# frozen_string_literal: true

require "rails_helper"

# @lat: [[abandoned-run-reclaim#Why ReclaimAbandonedSummaryRunsJob exists]]
RSpec.describe ReclaimAbandonedSummaryRunsJob do
  # Named off the vocabulary summary_run_arm_decision_spec already uses, so the
  # two files cannot be read for each other: this is `updated_at`, the
  # abandonment clock, and not the stale gate's `enqueued_at`.
  let(:abandoned_clock) { (GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER + 1.minute).ago }

  # update_all rather than the factory, because both columns this reads have to
  # be written without a callback bumping updated_at back to now.
  def stranded_provisioning(status, updated_at: nil, llm_summary: "A summary", llm_generated_at: nil)
    provisioning = create(
      :bill_llm_provisioning, bill: create(:bill),
      llm_summary: llm_summary, llm_generated_at: llm_generated_at
    )
    BillLlmProvisioning.where(id: provisioning.id).update_all(
      generation_status: status, updated_at: updated_at || abandoned_clock
    )
    provisioning.reload
  end

  before { allow(SwayLogging).to receive(:warn) }

  # THE CASE THAT HAD TO FAIL FIRST. No llm_summary and no llm_generated_at, so
  # #stale? is permanently false and the panel renders its disabled button with
  # no condition on it.
  it "frees a generating row on a bill that never produced a summary" do
    provisioning = stranded_provisioning("generating", llm_summary: nil, llm_generated_at: nil)

    expect(provisioning.stale?).to be(false)
    expect(described_class.new.perform).to eq(1)
    expect(provisioning.reload.generation_status).to eq("failed")
  end

  # The other stuck status, for the same reason the service covers both: a
  # `pending` row whose job never runs at all is stuck exactly as permanently.
  it "frees a pending row onto the terminal status a re-trigger can start from" do
    provisioning = stranded_provisioning("pending")

    described_class.new.perform

    provisioning.reload
    expect(provisioning.generation_status).to eq("skipped")
    expect(provisioning.can_enqueue?).to be(true)
  end

  # The counter-example, so the sweep cannot widen into "any in-flight row may
  # be taken". A run that is merely slow is untouched.
  it "leaves a run that is still writing alone" do
    provisioning = stranded_provisioning("generating", updated_at: 1.minute.ago)

    expect(described_class.new.perform).to eq(0)
    expect(provisioning.reload.generation_status).to eq("generating")
  end

  it "leaves a settled row alone however old it is" do
    provisioning = stranded_provisioning("completed")

    expect(described_class.new.perform).to eq(0)
    expect(provisioning.reload.generation_status).to eq("completed")
  end

  # It moves the row and stops. Deciding to spend money again stays with the
  # operator, so the sweep must not queue a run of its own.
  it "spends nothing and queues nothing" do
    stranded_provisioning("generating")
    allow(GenerateBillSummaryJob).to receive(:perform_later)

    expect(Llm::Client).not_to receive(:build)
    described_class.new.perform

    expect(GenerateBillSummaryJob).not_to have_received(:perform_later)
  end

  it "records the reclaim, because an abandoned run means a worker died" do
    stranded_provisioning("generating")

    described_class.new.perform

    expect(SwayLogging).to have_received(:warn)
      .with("reclaim_abandoned_summary_runs.reclaimed", any_args)
  end

  it "bounds one sweep so it cannot hold the writer lock over an unbounded set" do
    stub_const("#{described_class}::MAX_ROWS_PER_SWEEP", 1)
    2.times { stranded_provisioning("generating") }

    expect(described_class.new.perform).to eq(1)
  end

  # @lat: [[summary-run-release-single-home#What went wrong when a second caller reused it]]
  it "tells the operator what happened, because nothing re-arms the row after a sweep" do
    provisioning = stranded_provisioning("generating", llm_summary: nil, llm_generated_at: nil)

    described_class.new.perform

    expect(provisioning.reload.generation_error).to be_present
  end

  it "tells the operator what happened on the pending arm too" do
    provisioning = stranded_provisioning("pending", llm_summary: nil, llm_generated_at: nil)

    described_class.new.perform

    expect(provisioning.reload.generation_error).to be_present
  end

  # @lat: [[bill-summary-paste-hand-off-rule#settle_superseded_row: why the whole hand-off runs in one lock]]
  describe "a deferred paste hand-off" do
    def pasted_provisioning(status)
      provisioning = stranded_provisioning(status, llm_summary: "A summary a human wrote")
      BillLlmProvisioning.where(id: provisioning.id).update_all(
        summary_run_id: SummaryRunMarker.operator_paste, updated_at: abandoned_clock
      )
      provisioning.reload
    end

    it "finishes the hand-off the paste was promised, from generating" do
      provisioning = pasted_provisioning("generating")

      described_class.new.perform

      expect(provisioning.reload.generation_status).to eq("completed")
    end

    it "finishes the hand-off the paste was promised, from pending" do
      provisioning = pasted_provisioning("pending")

      described_class.new.perform

      expect(provisioning.reload.generation_status).to eq("completed")
    end

    it "leaves no failure message on a row it completed" do
      provisioning = pasted_provisioning("generating")

      described_class.new.perform

      expect(provisioning.reload.generation_error).to be_nil
    end
  end

  # @lat: [[summary-run-release-single-home#What went wrong when a second caller reused it]]
  it "finishes the sweep when one row raises, so a poison row cannot hide the rest" do
    poison = stranded_provisioning("generating", updated_at: abandoned_clock - 1.day)
    healthy = stranded_provisioning("generating")
    allow(SwayLogging).to receive(:log_exception)
    allow(SummaryRunRelease).to receive(:call).and_wrap_original do |original, provisioning, **kwargs|
      raise ActiveRecord::StatementInvalid, "database is locked" if provisioning.id == poison.id

      original.call(provisioning, **kwargs)
    end

    expect(described_class.new.perform).to eq(1)

    expect(poison.reload.generation_status).to eq("generating")
    expect(healthy.reload.generation_status).to eq("failed")
  end

  it "records the row it could not free, so a sweep failing on one row is visible" do
    poison = stranded_provisioning("generating", updated_at: abandoned_clock - 1.day)
    allow(SwayLogging).to receive(:log_exception)
    allow(SummaryRunRelease).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "database is locked")

    described_class.new.perform

    expect(SwayLogging).to have_received(:log_exception)
      .with("reclaim_abandoned_summary_runs.row_failed", hash_including(provisioning_id: poison.id))
  end

  # @lat: [[summary-run-release-message-history#The threshold is interpolated, not spelled out by hand]]
  # Fails on a reword that drops the figure back to a literal, on either arm.
  it "quotes the threshold it is actually released on, on both arms" do
    threshold = GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.inspect

    expect(SummaryRunRelease::RELEASED_UNSTARTED_ERROR).to include(threshold)
    expect(SummaryRunRelease::RELEASED_IN_FLIGHT_ERROR).to include(threshold)
  end

  # @lat: [[llm-summary-notice-phrase-pairing#LlmSummaryAbandonedRunNotice field notes]]
  # The other half of this pairing is pinned in
  # app/frontend/components/admin/creator/llm-summary/__tests__/BillCreatorLlmSummaryStatus.test.tsx.
  it "keeps the two phrases the Bill Creator's notices copy" do
    expect(SummaryRunRelease::RELEASED_UNSTARTED_ERROR).to include("never started")
    expect(SummaryRunRelease::RELEASED_IN_FLIGHT_ERROR).to include("stopped part-way")
  end

  # @lat: [[summary-run-release-message-history#One message could not be true of both arms]]
  describe "the sentence it leaves on the row" do
    it "makes no cost claim over a row released while it was spending" do
      provisioning = stranded_provisioning("generating", llm_summary: "A summary this run already paid for")

      described_class.new.perform

      reason = provisioning.reload.generation_error
      expect(reason).to eq(SummaryRunRelease::RELEASED_IN_FLIGHT_ERROR)
      expect(reason).not_to match(/no summary was made/i)
      expect(reason).not_to match(/nothing was charged/i)
    end

    # The other direction, so the fix cannot be over-corrected into dropping the
    # cost claim everywhere. On the `pending` arm it is provable: the row never
    # reached #arm_row_unless_owned!, and the state machine has no
    # generating -> pending edge, so a row still `pending` never built a client.
    it "still says nothing was charged on a row that never started" do
      provisioning = stranded_provisioning("pending")

      described_class.new.perform

      reason = provisioning.reload.generation_error
      expect(reason).to eq(SummaryRunRelease::RELEASED_UNSTARTED_ERROR)
      expect(reason).to include("nothing was charged")
    end

    # @lat: [[summary-run-release-message-history#One message could not be true of both arms]]
    it "does not deny the writes the click that armed the row made" do
      provisioning = create(
        :bill_llm_provisioning, :with_testimony, bill: create(:bill),
        llm_summary: nil, llm_generated_at: nil,
        supplemental_testimony: "Testimony the operator pasted with the click.",
        draft_org_positions: [
          {
            "org_name" => "Test Org",
            "stance" => "support",
            "summary" => "Test position",
            "evidence_retracted_at" => 2.minutes.ago.utc.iso8601
          }
        ]
      )
      BillLlmProvisioning.where(id: provisioning.id).update_all(
        generation_status: "pending", updated_at: abandoned_clock
      )

      described_class.new.perform

      reason = provisioning.reload.generation_error
      expect(reason).to eq(SummaryRunRelease::RELEASED_UNSTARTED_ERROR)
      expect(reason).to include("anything you typed was saved")
      expect(reason).not_to match(/anything on this bill is from before it/i)
      expect(provisioning.supplemental_testimony).to eq("Testimony the operator pasted with the click.")
    end

    # @lat: [[summary-run-release-message-history#One message could not be true of both arms]]
    it "does not credit an earlier run's summary to the run that stopped" do
      provisioning = stranded_provisioning(
        "generating", llm_summary: "Run one's summary.", llm_generated_at: 2.days.ago
      )

      described_class.new.perform

      reason = provisioning.reload.generation_error
      expect(reason).to eq(SummaryRunRelease::RELEASED_IN_FLIGHT_ERROR)
      expect(reason).not_to match(/what it saved before it stopped/i)
      expect(reason).to match(/may have saved part of its work/i)
    end

    # @lat: [[summary-run-release-hand-off-paste#Why a stale generation_error is cleared before the hand-off completes]]
    it "finishes a pasted row instead of releasing it with either message" do
      provisioning = stranded_provisioning("pending", llm_summary: "I typed this.")
      BillLlmProvisioning.where(id: provisioning.id).update_all(
        summary_run_id: SummaryRunMarker.operator_paste,
        llm_provider: "operator_paste",
        updated_at: abandoned_clock
      )

      described_class.new.perform

      provisioning.reload
      expect(provisioning.generation_status).to eq("completed")
      expect(provisioning.llm_summary).to eq("I typed this.")
      # @lat: [[abandoned-run-reclaim#Why ReclaimAbandonedSummaryRunsJob exists]]
      expect(provisioning.generation_error).to be_nil
      # The prop the browser branches on, so this example and the one below
      # differ in the value the panel reads and not only in the outcome.
      expect(JSON.parse(provisioning.to_builder.target!)["paste_owns_summary_run"]).to be(true)
    end

    # @lat: [[abandoned-run-reclaim#Why ReclaimAbandonedSummaryRunsJob exists]]
    it "releases a paste that has since been regenerated, marker gone and provider left behind" do
      provisioning = stranded_provisioning("pending", llm_summary: "I typed this.")
      BillLlmProvisioning.where(id: provisioning.id).update_all(
        summary_run_id: nil,
        llm_provider: "operator_paste",
        updated_at: abandoned_clock
      )

      described_class.new.perform

      provisioning.reload
      expect(provisioning.generation_status).to eq("skipped")
      expect(provisioning.generation_error).to eq(SummaryRunRelease::RELEASED_UNSTARTED_ERROR)
      # The prop the browser branches on says the same thing the sweep just did.
      expect(JSON.parse(provisioning.to_builder.target!)["paste_owns_summary_run"]).to be(false)
    end
  end

  # @lat: [[llm-summaries#Batch summarisation#Why the per-bill exemption needs its own ceiling]]
  describe "a row a batch owns" do
    def batch_owned_provisioning(summary_batch_expires_at:)
      provisioning = stranded_provisioning("generating", llm_summary: nil, llm_generated_at: nil)
      BillLlmProvisioning.where(id: provisioning.id).update_all(summary_batch_expires_at: summary_batch_expires_at)
      provisioning.reload
    end

    it "is left alone while its batch is still live, however long the sweep has been quiet" do
      provisioning = batch_owned_provisioning(summary_batch_expires_at: 1.hour.from_now)

      expect(described_class.new.perform).to eq(0)
      expect(provisioning.reload.generation_status).to eq("generating")
    end

    it "is reclaimed once its batch's own expiry has passed" do
      provisioning = batch_owned_provisioning(summary_batch_expires_at: 1.minute.ago)

      expect(described_class.new.perform).to eq(1)
      expect(provisioning.reload.generation_status).to eq("failed")
    end

    it "is reclaimed when no batch expiry was ever recorded" do
      provisioning = batch_owned_provisioning(summary_batch_expires_at: nil)

      expect(described_class.new.perform).to eq(1)
      expect(provisioning.reload.generation_status).to eq("failed")
    end
  end
end
