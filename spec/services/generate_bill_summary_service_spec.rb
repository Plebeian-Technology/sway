# frozen_string_literal: true

require "rails_helper"

# Unit coverage for the check-then-enqueue logic pulled out of
# BillsController#generate_summary/#regenerate_summary. Request specs cover
# HTTP; these pin what the service returns and changes.
RSpec.describe GenerateBillSummaryService do
  it "clears stale run state, enqueues the job, and returns :enqueued" do
    bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
    provisioning = create(:bill_llm_provisioning,
      bill: bill, diff_content: "pipeline diff payload", diff_generated_at: Time.current,
      summary_run_id: "stale-uuid", generation_error: "prior failure")

    outcome = nil
    expect {
      outcome = described_class.new(bill: bill, actor: create(:user)).call
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)

    expect(outcome).to eq(:enqueued)
    expect(provisioning.reload.summary_run_id).to be_nil
    expect(provisioning.generation_error).to be_nil
  end

  it "returns :no_pipeline_data when the bill has no source text at all (no provisioning, no diff, no extracted_text)" do
    bill = create(:bill)

    expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:no_pipeline_data)
  end

  it "returns :no_pipeline_data when provisioning exists but the bill has no source text" do
    bill = create(:bill)
    create(:bill_llm_provisioning, bill: bill, diff_content: nil)

    expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:no_pipeline_data)
  end

  it "enqueues for a non-amending bill with extracted_text but no diff and no provisioning row" do
    # Regression test: the old check required provisioning.diff_content,
    # so it did nothing for resolutions/appointments with extracted_text
    # but no diff. The service now creates the row itself.
    bill = create(:bill)
    bill.update!(extracted_text: "Full text of a resolution with no diff.")

    outcome = nil
    expect {
      outcome = described_class.new(bill: bill, actor: create(:user)).call
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)

    expect(outcome).to eq(:enqueued)
    provisioning = bill.reload.bill_llm_provisioning #: BillLlmProvisioning?
    expect(provisioning).to be_present
    expect(provisioning&.generation_status).to eq("pending")
  end

  it "enqueues when provisioning has blank diff_content but the bill has extracted_text" do
    bill = create(:bill)
    bill.update!(extracted_text: "Resolution text.")
    create(:bill_llm_provisioning, bill: bill, diff_content: nil)

    expect {
      expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:enqueued)
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)
  end

  it "returns :already_in_progress when a generation is already pending" do
    bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
    create(:bill_llm_provisioning, :with_diff_content, :pending, bill: bill)

    expect {
      expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:already_in_progress)
    }.not_to have_enqueued_job(GenerateBillSummaryJob)
  end

  # A job can leave the row as skipped after clearing a stale
  # backlog. Unlike pending, skipped is a dead end, so the service recovers
  # itself: reset to pending and queue a fresh job.
  it "self-heals (returns :enqueued) when a prior job left the row skipped" do
    bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
    provisioning = create(:bill_llm_provisioning, :with_diff_content, :skipped, bill: bill)

    outcome = nil
    expect {
      outcome = described_class.new(bill: bill, actor: create(:user)).call
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)

    expect(outcome).to eq(:enqueued)
    expect(provisioning.reload.generation_status).to eq("pending")
  end

  it "emits a summary_regenerate_triggered audit entry when regenerate: true" do
    bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
    create(:bill_llm_provisioning, bill: bill, diff_content: "x", diff_generated_at: Time.current)
    actor = create(:user)

    expect {
      described_class.new(bill: bill, actor: actor, regenerate: true).call
    }.to change(PipelineActivityLogEntry, :count).by(1)

    entry = PipelineActivityLogEntry.order(created_at: :desc).first #: PipelineActivityLogEntry
    expect(entry.event_type).to eq("summary_regenerate_triggered")
    expect(entry.actor_user_id).to eq(actor.id)
  end

  # The Bill Creator empty state reuses useRegenerateSummary, so Generate
  # summary POSTs to /regenerate_summary even for a never-summarized bill —
  # the right endpoint, but its entry said regeneration.
  it "records a FIRST generation as a generation, not a regeneration" do
    bill = create(:bill, external_id: "CB-24-0001", extracted_text: "Section 1. Text.")
    create(:bill_llm_provisioning, bill: bill, llm_summary: nil, diff_content: "x",
      diff_generated_at: Time.current)

    described_class.new(bill: bill, actor: create(:user), regenerate: true).call

    entry = PipelineActivityLogEntry.order(created_at: :desc).first #: PipelineActivityLogEntry
    expect(entry.event_type).to eq("summary_regenerate_triggered")
    expect(entry.payload["first_generation"]).to be(true)
    expect(entry.message).to include("summary generation")
    expect(entry.message).not_to include("regeneration")
    expect(entry.title).not_to include("regeneration")
  end

  it "records a regeneration as a regeneration when a summary already exists" do
    bill = create(:bill, external_id: "CB-24-0002", extracted_text: "Section 1. Text.")
    create(:bill_llm_provisioning, bill: bill, llm_summary: "A prior summary.",
      diff_content: "x", diff_generated_at: Time.current)

    described_class.new(bill: bill, actor: create(:user), regenerate: true).call

    entry = PipelineActivityLogEntry.order(created_at: :desc).first #: PipelineActivityLogEntry
    expect(entry.payload["first_generation"]).to be(false)
    expect(entry.message).to include("summary regeneration")
    expect(entry.title).to include("regeneration")
  end

  # No extracted_text on purpose: the incoming paste is what makes this
  # runnable?, and that is worth keeping visible in the fixture.
  it "persists supplemental_testimony on the generate path" do
    bill = create(:bill)
    provisioning = create(:bill_llm_provisioning, bill: bill, diff_content: "x", diff_generated_at: Time.current)

    described_class.new(bill: bill, actor: create(:user), supplemental_testimony: "extra context").call

    expect(provisioning.reload.supplemental_testimony).to eq("extra context")
  end

  # This used to assert the OPPOSITE, that generate writes no audit entry,
  # with nothing saying why one money-spending trigger went unaudited.
  # Generate is what an operator reaches on a failed row.
  it "logs an audit entry on the generate path too" do
    bill = create(:bill)
    create(:bill_llm_provisioning, bill: bill, diff_content: "x", diff_generated_at: Time.current)

    expect {
      described_class.new(bill: bill, actor: create(:user), supplemental_testimony: "extra context").call
    }.to change(PipelineActivityLogEntry, :count).by(1)
  end

  # And the two are still told apart, by the flag that exists for it rather
  # than by one of them being missing.
  it "marks the generate path as a first generation" do
    bill = create(:bill)
    create(:bill_llm_provisioning, bill: bill, diff_content: "x", diff_generated_at: Time.current)

    described_class.new(bill: bill, actor: create(:user), supplemental_testimony: "extra context").call

    entry = PipelineActivityLogEntry.order(created_at: :desc).first #: PipelineActivityLogEntry
    expect(entry.payload["first_generation"]).to be(true)
  end

  # The check used to run against data already in memory. Another caller
  # can flip the row to :pending after a stale load; with_lock re-reads
  # under lock, so the service backs out.
  it "returns :already_in_progress and does NOT enqueue when the row was flipped to pending behind a stale in-memory read" do
    bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
    provisioning = create(:bill_llm_provisioning, :completed,
      bill: bill, diff_content: "pipeline diff payload", diff_generated_at: Time.current)
    # The copy in memory still says :completed — what another caller saw before
    # it changed the database row ...
    expect(provisioning.generation_status).to eq("completed")
    # ... while that other caller has already committed :pending to the row.
    BillLlmProvisioning.where(id: provisioning.id).update_all(generation_status: "pending")
    # The service has to load THIS stale object, then re-read it under the lock.
    allow(bill).to receive(:bill_llm_provisioning).and_return(provisioning)

    outcome = nil
    expect {
      outcome = described_class.new(bill: bill, actor: create(:user)).call
    }.not_to have_enqueued_job(GenerateBillSummaryJob)

    expect(outcome).to eq(:already_in_progress)
  end

  # One source_present? check used to gate the WHOLE job, including
  # org-positions, which uses none of those inputs — so clean testimony
  # with a failed PDF could never generate positions at all.
  describe "the two calls are gated independently (B4-WR-04)" do
    it "enqueues for a testimony-only bill with no bill source text" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, extracted_testimony: "Testimony of the Tenants Union.")

      outcome = nil
      expect {
        outcome = described_class.new(bill: bill, actor: create(:user)).call
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)

      expect(outcome).to eq(:enqueued)
    end

    it "enqueues when the operator's supplemental testimony is the only evidence" do
      bill = create(:bill)

      outcome = nil
      expect {
        outcome = described_class.new(
          bill: bill, actor: create(:user), supplemental_testimony: "Pasted hearing testimony."
        ).call
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)

      expect(outcome).to eq(:enqueued)
    end

    it "persists that paste rather than dropping it at the source check" do
      bill = create(:bill)

      described_class.new(
        bill: bill, actor: create(:user), supplemental_testimony: "Pasted hearing testimony."
      ).call

      expect(bill.reload.bill_llm_provisioning&.supplemental_testimony).to eq("Pasted hearing testimony.")
    end

    it "still returns :no_pipeline_data when there is neither source text nor any testimony" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, diff_content: nil)

      expect {
        expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:no_pipeline_data)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "enqueues a job when there is no source text or testimony, but an approved reporting article is present" do
      bill = create(:bill, extracted_text: nil)
      create(:bill_llm_provisioning, bill: bill, diff_content: nil)
      article = create(:news_article, article_kind: "reporting")
      tv = create(:news_article_text_version, :extracted, news_article: article, text: "Factual news report.")
      create(:bill_news_article, :approved, bill: bill, news_article: article, current_text_version: tv)

      expect {
        expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "enqueues a job when there is no source text or testimony, but an approved opinion commentary article is present" do
      bill = create(:bill, extracted_text: nil)
      create(:bill_llm_provisioning, bill: bill, diff_content: nil)
      article = create(:news_article, :op_ed)
      tv = create(:news_article_text_version, :extracted, news_article: article, text: "Op-ed text supporting housing reform.")
      create(:bill_news_article, :approved, :support, bill: bill, news_article: article, current_text_version: tv)

      expect {
        expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "still returns :no_pipeline_data when reporting articles exist but none are approved" do
      bill = create(:bill, extracted_text: nil)
      create(:bill_llm_provisioning, bill: bill, diff_content: nil)
      article = create(:news_article, article_kind: "reporting")
      tv = create(:news_article_text_version, :extracted, news_article: article, text: "Factual news report.")
      create(:bill_news_article, approved: false, bill: bill, news_article: article, current_text_version: tv)

      expect {
        expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:no_pipeline_data)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "does not self-provision a row for a bill with nothing to run" do
      # The Bill Creator's empty state decides what to show by whether a
      # provisioning row exists, so a call that goes nowhere must not leave a
      # stray row behind.
      bill = create(:bill)

      described_class.new(bill: bill, actor: create(:user)).call

      expect(bill.reload.bill_llm_provisioning).to be_nil
    end
  end

  # @lat: [[explanation/llm-summaries#Runs are marked and reclaimable#Why the reclaim judgement lives on the row]]
  describe "reclaiming a row abandoned mid-flight (B4-WR-02)" do
    it "re-arms a `generating` row whose worker died and returns :enqueued" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      provisioning = create(:bill_llm_provisioning, :with_diff_content, :generating, bill: bill)
      provisioning.update_columns(updated_at: 3.hours.ago)
      allow(SwayLogging).to receive(:warn)

      outcome = nil
      expect {
        outcome = described_class.new(bill: bill, actor: create(:user)).call
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)

      expect(outcome).to eq(:enqueued)
      expect(provisioning.reload.generation_status).to eq("pending")
    end

    it "logs the reclaim so an abandoned run is visible, not silently absorbed" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      provisioning = create(:bill_llm_provisioning, :with_diff_content, :generating, bill: bill)
      provisioning.update_columns(updated_at: 3.hours.ago)
      allow(SwayLogging).to receive(:warn)

      described_class.new(bill: bill, actor: create(:user)).call

      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary_service.reclaimed_abandoned_run", hash_including(bill_id: bill.id)
      )
    end

    it "does NOT reclaim a healthy in-flight run" do
      # The job's own worst case is about 20 minutes (SDK retries nested inside
      # three attempts with growing backoff), so a `generating` row touched
      # recently is a run still going, not a dead one.
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      create(:bill_llm_provisioning, :with_diff_content, :generating, bill: bill)

      expect {
        expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:already_in_progress)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    # Both halves of the same check, or this fixes one of two places that share
    # the problem. A `pending` row is stuck just as permanently when the job that
    # was supposed to clear it never runs at all.
    it "re-arms a `pending` row that no job ever picked up" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      provisioning = create(:bill_llm_provisioning, :with_diff_content, :pending, bill: bill)
      provisioning.update_columns(updated_at: 3.hours.ago)
      allow(SwayLogging).to receive(:warn)

      outcome = nil
      expect {
        outcome = described_class.new(bill: bill, actor: create(:user)).call
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)

      expect(outcome).to eq(:enqueued)
      expect(provisioning.reload.generation_status).to eq("pending")
    end

    it "does NOT reclaim a freshly-enqueued pending row (the double-click guard still holds)" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      create(:bill_llm_provisioning, :with_diff_content, :pending, bill: bill)

      expect {
        expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:already_in_progress)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end
  end

  # B22-03: #call commits enqueue! inside the lock, then enqueues the job,
  # which can raise SQLITE_BUSY — leaving the row pending with no job and
  # no way to reach it. It reverts to skipped instead.
  describe "when the job cannot be queued after the row is armed" do
    it "does not leave the row pending with no job coming for it" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      provisioning = create(:bill_llm_provisioning, :with_diff_content, bill: bill)
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)
      allow(GenerateBillSummaryJob).to receive(:perform_later)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      described_class.new(bill: bill, actor: create(:user)).call

      expect(provisioning.reload.generation_status).to eq("skipped")
      expect(provisioning.can_enqueue?).to be(true)
    end

    it "tells the operator rather than handing them a 500 over a row it just armed" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      create(:bill_llm_provisioning, :with_diff_content, bill: bill)
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)
      allow(GenerateBillSummaryJob).to receive(:perform_later)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      outcome = described_class.new(bill: bill, actor: create(:user)).call

      expect(outcome).to eq(:enqueue_failed)
    end

    it "writes no audit entry for a generation that was never triggered" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      create(:bill_llm_provisioning, :with_diff_content, bill: bill)
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)
      allow(GenerateBillSummaryJob).to receive(:perform_later)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      described_class.new(bill: bill, actor: create(:user)).call

      expect(PipelineActivityLogEntry.where(event_type: "summary_regenerate_triggered").count).to eq(0)
    end

    # B23-04: clearing summary_run_id IS the override, the one column
    # standing between hand-written work and a background run. Losing it
    # let a pipeline run overwrite the operator's summary.
    it "puts the operator's paste marker back when the click it belonged to was refused" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      paste_marker = SummaryRunMarker.operator_paste
      provisioning = create(
        :bill_llm_provisioning, :with_diff_content, bill: bill,
        summary_run_id: paste_marker, llm_summary: "A summary an operator wrote by hand",
        llm_provider: "operator_paste"
      )
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)
      allow(GenerateBillSummaryJob).to receive(:perform_later)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      described_class.new(bill: bill, actor: create(:user)).call

      expect(provisioning.reload.summary_run_id).to eq(paste_marker)
      expect(provisioning.generation_status).to eq("skipped")
    end

    # The other direction, so the restore can't widen into put back
    # whatever was there: a run claim or purchase receipt is not the
    # operator's work, and clearing it is the ordinary supersede.
    it "restores nothing when the marker it cleared was not a paste" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      provisioning = create(
        :bill_llm_provisioning, :with_diff_content, bill: bill, summary_run_id: "an-older-runs-job-id"
      )
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)
      allow(GenerateBillSummaryJob).to receive(:perform_later)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      described_class.new(bill: bill, actor: create(:user)).call

      expect(provisioning.reload.summary_run_id).to be_nil
    end

    # BE25-01: the row must SAY WHY, since the panel prints what a skipped
    # row carries. Two different writers reach skipped for different
    # causes; only one used to say which.
    it "says why the row is skipped, in words that fit a job that was never queued" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      provisioning = create(:bill_llm_provisioning, :with_diff_content, bill: bill)
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)
      allow(GenerateBillSummaryJob).to receive(:perform_later)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      described_class.new(bill: bill, actor: create(:user)).call

      reason = provisioning.reload.generation_error
      expect(reason).to eq(described_class::UNQUEUED_ERROR)
      expect(reason).not_to include("queue")
      expect(reason).to include("Nothing was charged")
    end

    # BE26-02: release_unqueued_row! must not undo a REPLACING paste's
    # evidence_retracted_at stamp — the operator's paste is theirs, even
    # though the message said nothing had happened.
    it "does not claim the bill was left as it was after replacing its testimony" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      provisioning = create(
        :bill_llm_provisioning, :with_diff_content, bill: bill,
        supplemental_testimony: "Testimony of the Maryland Tenants Union.",
        draft_org_positions: [{"org_name" => "ACLU", "stance" => "support", "summary" => "Testified."}]
      )
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)
      allow(GenerateBillSummaryJob).to receive(:perform_later)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      described_class.new(
        bill: bill, actor: create(:user), supplemental_testimony: "Testimony of the Baltimore Renters Alliance."
      ).call

      provisioning.reload
      # The two writes the old sentence denied, asserted here so the sentence
      # cannot be reworded back over them.
      expect(provisioning.supplemental_testimony).to eq("Testimony of the Baltimore Renters Alliance.")
      expect(provisioning.draft_org_positions&.first&.[]("evidence_retracted_at")).to be_present

      reason = provisioning.generation_error
      expect(reason).not_to match(/left as it was/i)
      expect(reason).to include("anything you typed was saved")
    end

    it "keeps the failure in the permanent record" do
      bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      create(:bill_llm_provisioning, :with_diff_content, bill: bill)
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)
      allow(GenerateBillSummaryJob).to receive(:perform_later)
        .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

      described_class.new(bill: bill, actor: create(:user)).call

      expect(SwayLogging).to have_received(:log_exception).with(
        "generate_bill_summary_service.enqueue_failed", hash_including(bill_id: bill.id)
      )
    end
  end

  it "enqueues GenerateBillSummaryJob exactly once on the happy path (no double-enqueue)" do
    bill = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
    create(:bill_llm_provisioning, :with_diff_content, bill: bill, diff_generated_at: Time.current)

    expect {
      expect(described_class.new(bill: bill, actor: create(:user)).call).to eq(:enqueued)
    }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id).exactly(:once)
  end

  # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
  describe "summarization_model override with OpenRouter choices" do
    let(:bill) do
      b = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      create(:bill_llm_provisioning, :with_diff_content, bill: b, diff_generated_at: Time.current)
      b
    end

    it "accepts OpenRouter choices and enqueues with the model override" do
      expect {
        outcome = described_class.new(bill: bill, actor: create(:user), summarization_model: "Deepseek Pro Latest").call
        expect(outcome).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summarization_model: "Deepseek Pro Latest")
    end

    it "accepts dynamic OpenRouter choices in AdminSetting.offered_models and enqueues" do
      AdminSetting.singleton.update!(offered_models: AdminSetting::SUPPORTED_MODELS + ["openai/gpt-4o"])

      expect {
        outcome = described_class.new(bill: bill, actor: create(:user), summarization_model: "openai/gpt-4o").call
        expect(outcome).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summarization_model: "openai/gpt-4o")
    end

    it "refuses dynamic model strings absent from AdminSetting.offered_models" do
      expect {
        outcome = described_class.new(bill: bill, actor: create(:user), summarization_model: "openai/gpt-4o").call
        expect(outcome).to eq(:unsupported_model)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "refuses unoffered model strings and returns :unsupported_model without enqueuing" do
      expect {
        outcome = described_class.new(bill: bill, actor: create(:user), summarization_model: "unsupported-model").call
        expect(outcome).to eq(:unsupported_model)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end
  end

  describe "per-run summary_instructions" do
    let(:bill) do
      b = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
      create(:bill_llm_provisioning, :with_diff_content, bill: b, diff_generated_at: Time.current)
      b
    end
    let(:actor) { create(:user) }

    it "enqueues with normalized summary_instructions when valid instructions are given" do
      expect {
        outcome = described_class.new(
          bill: bill, actor: actor,
          summary_instructions: " \t\nFocus on the property tax rate.\n "
        ).call
        expect(outcome).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(
        bill.id, summary_instructions: "Focus on the property tax rate."
      )
    end

    it "enqueues with both summarization_model and summary_instructions when both are given" do
      expect {
        outcome = described_class.new(
          bill: bill, actor: actor,
          summarization_model: "claude-opus-5-5",
          summary_instructions: "Highlight tax changes."
        ).call
        expect(outcome).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(
        bill.id,
        summarization_model: "claude-opus-5-5",
        summary_instructions: "Highlight tax changes."
      )
    end

    it "preserves non-ASCII whitespace such as U+00A0 alone without dropping it as blank" do
      expect {
        outcome = described_class.new(bill: bill, actor: actor, summary_instructions: "\u00A0").call
        expect(outcome).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summary_instructions: "\u00A0")
    end

    it "preserves U+00A0 surrounded by ASCII whitespace" do
      expect {
        outcome = described_class.new(
          bill: bill, actor: actor, summary_instructions: " \t\r\n\f\v\u00A0\t\n "
        ).call
        expect(outcome).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summary_instructions: "\u00A0")
    end

    it "omits summary_instructions keyword when nil, empty, or whitespace-only" do
      [nil, "", "   \t\r\n\f\v  "].each do |val|
        b = create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.")
        create(:bill_llm_provisioning, :with_diff_content, bill: b, diff_generated_at: Time.current)

        expect {
          described_class.new(bill: b, actor: actor, summary_instructions: val).call
        }.to have_enqueued_job(GenerateBillSummaryJob).with(b.id)
      end
    end

    it "returns :invalid_summary_instructions when summary_instructions is not a string (hash)" do
      expect {
        outcome = described_class.new(
          bill: bill, actor: actor, summary_instructions: {invalid: "type"}
        ).call
        expect(outcome).to eq(:invalid_summary_instructions)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)

      expect(PipelineActivityLogEntry.where(event_type: "summary_regenerate_triggered")).to be_empty
    end

    it "returns :invalid_summary_instructions when summary_instructions is not a string (array)" do
      expect {
        outcome = described_class.new(
          bill: bill, actor: actor, summary_instructions: ["invalid"]
        ).call
        expect(outcome).to eq(:invalid_summary_instructions)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "accepts exactly 2,000 code points including an astral character" do
      valid_text = ("a" * 1999) + "\u{1F600}"
      expect(valid_text.length).to eq(2000)

      expect {
        outcome = described_class.new(
          bill: bill, actor: actor, summary_instructions: valid_text
        ).call
        expect(outcome).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summary_instructions: valid_text)
    end

    it "returns :invalid_summary_instructions for 2,001 code points (2,000 ASCII + astral character)" do
      over_limit = ("a" * 2000) + "\u{1F600}"
      expect(over_limit.length).to eq(2001)

      expect {
        outcome = described_class.new(
          bill: bill, actor: actor, summary_instructions: over_limit
        ).call
        expect(outcome).to eq(:invalid_summary_instructions)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "instructions alone do not satisfy runnable? (returns :no_pipeline_data when bill has no source or testimony)" do
      sourceless_bill = create(:bill)
      outcome = described_class.new(
        bill: sourceless_bill, actor: actor, summary_instructions: "Instructions with no source"
      ).call
      expect(outcome).to eq(:no_pipeline_data)
    end
  end

  describe "reasoning_effort option" do
    let(:actor) { create(:user) }
    let(:bill) { create(:bill, extracted_text: "Enacting legislation text.") }

    it "enqueues GenerateBillSummaryJob with reasoning_effort when valid" do
      AdminSetting.singleton.update!(summarization_model: "Opus Latest")

      expect {
        outcome = described_class.new(
          bill: bill,
          actor: actor,
          reasoning_effort: "high"
        ).call
        expect(outcome).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(
        bill.id,
        reasoning_effort: "high"
      )
    end

    it "normalizes blank reasoning_effort to nil and enqueues without reasoning_effort" do
      expect {
        outcome = described_class.new(
          bill: bill,
          actor: actor,
          reasoning_effort: "   "
        ).call
        expect(outcome).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)
    end

    it "returns :unsupported_reasoning_effort when reasoning_effort is invalid" do
      expect {
        outcome = described_class.new(
          bill: bill,
          actor: actor,
          reasoning_effort: "ultra"
        ).call
        expect(outcome).to eq(:unsupported_reasoning_effort)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "returns :unsupported_reasoning_effort when reasoning_effort is provided for a non-reasoning per-run model" do
      expect {
        outcome = described_class.new(
          bill: bill,
          actor: actor,
          summarization_model: "claude-haiku-5-5",
          reasoning_effort: "high"
        ).call
        expect(outcome).to eq(:unsupported_reasoning_effort)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "returns :unsupported_reasoning_effort when reasoning_effort is provided and standing model is non-reasoning" do
      AdminSetting.singleton.update!(summarization_model: "claude-haiku-5-5")

      expect {
        outcome = described_class.new(
          bill: bill,
          actor: actor,
          reasoning_effort: "high"
        ).call
        expect(outcome).to eq(:unsupported_reasoning_effort)
      }.not_to have_enqueued_job(GenerateBillSummaryJob)
    end

    it "accepts reasoning_effort: 'default' for a reasoning model to override a standing effort to default" do
      AdminSetting.singleton.update!(
        summarization_model: "Opus Latest",
        summarization_reasoning_effort: "high"
      )

      expect {
        outcome = described_class.new(
          bill: bill,
          actor: actor,
          summarization_model: "Opus Latest",
          reasoning_effort: "default"
        ).call
        expect(outcome).to eq(:enqueued)
      }.to have_enqueued_job(GenerateBillSummaryJob).with(
        bill.id,
        summarization_model: "Opus Latest",
        reasoning_effort: "default"
      )
    end
  end
end
