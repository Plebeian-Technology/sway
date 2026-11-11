# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Batch summarisation#Submitting a run's summarisation as chunked batches]]
RSpec.describe SummaryBatchSubmission do
  let(:sway_locale) { SwayLocale.find_by(city: "baltimore") || create(:sway_locale, :baltimore) }
  let(:run) { create(:legislation_pipeline_run, bill: nil) }
  let(:submitted_chunks) { [] }
  let(:batch_expires_at) { 23.hours.from_now.change(usec: 0) }

  around { |example| with_app_config(:llm, llm_provider: "claude") { example.run } }

  before do
    AdminSetting.singleton.update!(summary_batch_enabled: true)
    allow(Llm::ClaudeBatchService).to receive(:submit) do |items:|
      submitted_chunks << items
      double(id: "msgbatch_#{submitted_chunks.length}", expires_at: batch_expires_at)
    end
  end

  def batchable_bill(external_id, days_ago, text: "Section 1. The Mayor shall report annually.", testimony: true)
    bill = create(:bill, external_id: external_id, sway_locale: sway_locale,
      extracted_text: text, scheduled_release_date_utc: days_ago.days.ago)
    traits = testimony ? [:with_testimony] : []
    create(:bill_llm_provisioning, *traits, bill: bill)
    bill.reload
  end

  def accumulate_bill(submission, bill)
    bill_run = create(:pipeline_run_bill,
      legislation_pipeline_run: run, bill_external_id: bill.external_id)
    submission.accumulate(bill_run, bill)
    bill_run
  end

  def submitted_custom_ids
    submitted_chunks.flatten.map(&:custom_id)
  end

  def provisioning_for(bill)
    BillLlmProvisioning.find_by(bill_id: bill.id) || raise("no provisioning row for #{bill.external_id}")
  end

  describe ".for" do
    it "serves an all-bills run under the Claude provider" do
      expect(described_class.for(run: run)).to be_a(described_class)
    end

    it "declines a single-bill run, which keeps the synchronous path" do
      bill = batchable_bill("SBS-SINGLE", 400)
      single = create(:legislation_pipeline_run, bill: bill)

      expect(described_class.for(run: single)).to be_nil
    end

    it "declines a run configured for a provider that has no batch API" do
      with_app_config(:llm, llm_provider: "llamacpp") do
        expect(described_class.for(run: run)).to be_nil
      end
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#Why the batch path is off until it is switched on]]
    it "declines every run while the admin switch is off, which is how it ships" do
      AdminSetting.singleton.update!(summary_batch_enabled: false)

      expect(described_class.for(run: run)).to be_nil
    end

    context "when summarization model routes to OpenRouter" do
      [
        "Deepseek Pro Latest",
        "Deepseek Flash Latest",
        "OpenRouter Auto"
      ].each do |openrouter_model|
        it "declines batch submission for #{openrouter_model} even when batch toggle is on" do
          AdminSetting.singleton.update_columns(
            summary_batch_enabled: true,
            summarization_model: openrouter_model
          )

          expect(described_class.for(run: run)).to be_nil
          expect(AdminSetting.singleton.reload.summary_batch_enabled).to be(true)
        end

        it "declines batch submission if #{openrouter_model} is chosen before enabling batch toggle" do
          AdminSetting.singleton.update_columns(
            summary_batch_enabled: false,
            summarization_model: openrouter_model
          )
          AdminSetting.singleton.update!(summary_batch_enabled: true)

          expect(described_class.for(run: run)).to be_nil
        end

        it "declines batch submission if #{openrouter_model} is chosen after enabling batch toggle" do
          AdminSetting.singleton.update!(
            summary_batch_enabled: true,
            summarization_model: "claude-haiku-5-5"
          )
          expect(described_class.for(run: run)).to be_a(described_class)

          AdminSetting.singleton.update_columns(summarization_model: openrouter_model)
          expect(described_class.for(run: run)).to be_nil
        end
      end

      # @lat: [[llm-summaries#Batch summarisation#Which runs submit a batch at all]]
      it "refuses direct construction when the current summary route is OpenRouter" do
        AdminSetting.singleton.update_columns(summarization_model: "Deepseek Pro Latest")

        expect { described_class.new(run: run) }
          .to raise_error(Llm::UnknownRouteError, /requires a Claude route/)
      end
    end
  end

  describe "#accumulate" do
    # @lat: [[llm-summaries#Batch summarisation#Which runs submit a batch at all]]
    it "keeps the Claude model selected for the batch if settings change before accumulation" do
      AdminSetting.singleton.update_columns(summarization_model: "claude-sonnet-5-5")
      submission = described_class.for(run: run)
      AdminSetting.singleton.update_columns(summarization_model: "Deepseek Pro Latest")
      bill = batchable_bill("SBS-ROUTE-PIN", 400, testimony: false)

      accumulate_bill(submission, bill)
      submission.submit!

      expect(submitted_chunks.flatten.map(&:model)).to eq(["claude-sonnet-5-5"])
      expect(run.pipeline_run_summary_batches.first.model).to eq("claude-sonnet-5-5")
    end

    # @lat: [[llm-summaries#Batch summarisation#Which runs submit a batch at all]]
    it "keeps the batch record model if settings change after accumulation" do
      AdminSetting.singleton.update_columns(summarization_model: "claude-sonnet-5-5")
      submission = described_class.for(run: run)
      bill = batchable_bill("SBS-ROUTE-PIN-SUBMIT", 400, testimony: false)
      accumulate_bill(submission, bill)
      AdminSetting.singleton.update_columns(summarization_model: "Deepseek Pro Latest")

      submission.submit!

      expect(submitted_chunks.flatten.map(&:model)).to eq(["claude-sonnet-5-5"])
      expect(run.pipeline_run_summary_batches.first.model).to eq("claude-sonnet-5-5")
    end

    it "builds one item for a bill that earns only a summary" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-SUMMARY-ONLY", 401, testimony: false)

      expect(submission.accumulate(pipeline_run_bill_for(bill), bill)).to eq(1)
    end

    it "names that one item as the summary answer type" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-SUMMARY-ID", 402, testimony: false)
      accumulate_bill(submission, bill)

      submission.submit!

      expect(submitted_custom_ids).to eq(["bill__#{bill.id}__summary"])
    end

    it "builds one item for a bill that earns only positions" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-POSITIONS-ONLY", 403, text: nil)

      expect(submission.accumulate(pipeline_run_bill_for(bill), bill)).to eq(1)
    end

    it "names that one item as the positions answer type" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-POSITIONS-ID", 404, text: nil)
      accumulate_bill(submission, bill)

      submission.submit!

      expect(submitted_custom_ids).to eq(["bill__#{bill.id}__positions"])
    end

    it "does not fan out BillNewsArticleFetchJob when accumulating batch summary items" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-NO-AUTO-NEWS", 405, testimony: false)

      expect {
        accumulate_bill(submission, bill)
      }.not_to have_enqueued_job(BillNewsArticleFetchJob)
    end

    it "does not call BillNewsArticleFetchService directly when accumulating batch summary items" do
      expect(BillNewsArticleFetchService).not_to receive(:call)
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-NO-DIRECT-NEWS", 406, testimony: false)

      accumulate_bill(submission, bill)
    end

    it "builds both items for a bill that earns both" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-BOTH", 405)

      expect(submission.accumulate(pipeline_run_bill_for(bill), bill)).to eq(2)
    end

    it "builds no item for a bill an operator's paste owns" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-PASTE", 406)
      provisioning_for(bill).update_columns(summary_run_id: SummaryRunMarker.operator_paste)

      expect(submission.accumulate(pipeline_run_bill_for(bill), bill.reload)).to eq(0)
    end

    it "builds no item for a bill with neither source text nor testimony" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-NEITHER", 407, text: nil, testimony: false)

      expect(submission.accumulate(pipeline_run_bill_for(bill), bill)).to eq(0)
    end

    it "creates the provisioning row for a bill that has none, so eligibility has something to read" do
      submission = described_class.new(run: run)
      bill = create(:bill, external_id: "SBS-NO-ROW", sway_locale: sway_locale,
        extracted_text: "Section 1.", scheduled_release_date_utc: 408.days.ago)

      submission.accumulate(pipeline_run_bill_for(bill), bill)

      expect(bill.reload.bill_llm_provisioning).to be_present
    end
  end

  describe "#submit!" do
    it "submits nothing when no bill earned an item" do
      submission = described_class.new(run: run)
      accumulate_bill(submission, batchable_bill("SBS-EMPTY", 410, text: nil, testimony: false))

      submission.submit!

      expect(Llm::ClaudeBatchService).not_to have_received(:submit)
    end

    it "records one batch row per chunk" do
      submission = described_class.new(run: run)
      AdminSetting.singleton.update!(summary_batch_chunk_size: 2)
      3.times { |n| accumulate_bill(submission, batchable_bill("SBS-CHUNK-#{n}", 420 + n)) }

      submission.submit!

      expect(run.pipeline_run_summary_batches.count).to eq(2)
    end

    it "puts a bill's two items in the same batch, because the chunk counts bills" do
      submission = described_class.new(run: run)
      AdminSetting.singleton.update!(summary_batch_chunk_size: 2)
      3.times { |n| accumulate_bill(submission, batchable_bill("SBS-PAIR-#{n}", 430 + n)) }

      submission.submit!

      expect(submitted_chunks.map(&:length)).to eq([4, 2])
    end

    it "submits one batch when the chunk size covers every bill" do
      submission = described_class.new(run: run)
      AdminSetting.singleton.update!(summary_batch_chunk_size: 25)
      3.times { |n| accumulate_bill(submission, batchable_bill("SBS-ONE-#{n}", 440 + n)) }

      submission.submit!

      expect(run.pipeline_run_summary_batches.count).to eq(1)
    end

    it "records each batch's id as the API reported it" do
      submission = described_class.new(run: run)
      AdminSetting.singleton.update!(summary_batch_chunk_size: 1)
      2.times { |n| accumulate_bill(submission, batchable_bill("SBS-ID-#{n}", 450 + n)) }

      submission.submit!

      expect(run.pipeline_run_summary_batches.pluck(:batch_id)).to contain_exactly("msgbatch_1", "msgbatch_2")
    end

    it "records how many items the chunk actually submitted" do
      submission = described_class.new(run: run)
      accumulate_bill(submission, batchable_bill("SBS-ITEM-COUNT-BOTH", 462))
      accumulate_bill(submission, batchable_bill("SBS-ITEM-COUNT-ONE", 463, testimony: false))

      submission.submit!

      expect(run.pipeline_run_summary_batches.first.item_count).to eq(3)
    end

    it "records the expiry the API returned rather than a locally computed 24 hours" do
      submission = described_class.new(run: run)
      accumulate_bill(submission, batchable_bill("SBS-EXPIRY", 460))

      submission.submit!

      expect(run.pipeline_run_summary_batches.first.expires_at).to be_within(1.second).of(batch_expires_at)
    end

    it "stamps submitted_at on every batch row" do
      submission = described_class.new(run: run)
      accumulate_bill(submission, batchable_bill("SBS-SUBMITTED-AT", 461))

      submission.submit!

      expect(run.pipeline_run_summary_batches.first.submitted_at).to be_present
    end

    it "persists the model on the pipeline_run_summary_batches record" do
      AdminSetting.singleton.update!(summarization_model: "claude-sonnet-5-5")
      submission = described_class.new(run: run)
      accumulate_bill(submission, batchable_bill("SBS-MODEL", 462))

      submission.submit!

      expect(run.pipeline_run_summary_batches.first.model).to eq("claude-sonnet-5-5")
    end

    it "builds every custom_id through Llm::BatchCustomId, so none can reject the whole batch" do
      submission = described_class.new(run: run)
      3.times { |n| accumulate_bill(submission, batchable_bill("SBS-CUSTOMID-#{n}", 470 + n)) }

      submission.submit!

      expect(submitted_custom_ids).to all(satisfy { |id| Llm::BatchCustomId.valid?(id) })
    end

    it "sends the summarization model the admin settings name" do
      AdminSetting.singleton.update!(summarization_model: "claude-sonnet-5-5")
      submission = described_class.new(run: run)
      accumulate_bill(submission, batchable_bill("SBS-MODEL", 480))

      submission.submit!

      expect(submitted_chunks.flatten.map(&:model).uniq).to eq(["claude-sonnet-5-5"])
    end
  end

  describe "arming the rows a batch owns" do
    it "arms each submitted bill's provisioning row" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-ARM", 490)
      accumulate_bill(submission, bill)

      submission.submit!

      expect(provisioning_for(bill).reload.generation_status).to eq("generating")
    end

    it "writes the batch id the row belongs to" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-ARM-ID", 491)
      accumulate_bill(submission, bill)

      submission.submit!

      expect(provisioning_for(bill).reload.summary_batch_id).to eq("msgbatch_1")
    end

    it "writes the batch expiry, which is what exempts the row from the abandoned sweep" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-ARM-EXPIRY", 492)
      accumulate_bill(submission, bill)

      submission.submit!

      expect(provisioning_for(bill).reload.summary_batch_awaited?).to be(true)
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#Why the evidence digest is stamped at submit time]]
    it "stamps the testimony digest the positions half will be checked against hours later" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-ARM-DIGEST", 497)
      accumulate_bill(submission, bill)

      submission.submit!

      provisioning = provisioning_for(bill).reload
      expect(provisioning.summary_batch_testimony_digest).to eq(provisioning.testimony_digest)
    end

    it "claims the row with an identity derived from the batch and the bill" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-ARM-MARKER", 493)
      accumulate_bill(submission, bill)

      submission.submit!

      expect(provisioning_for(bill).reload.summary_run_id).to eq(
        SummaryRunMarker.run_claim(SummaryRunMarker.batch_run_id(batch_id: "msgbatch_1", bill_id: bill.id))
      )
    end

    it "gives two bills in one batch different claims, since summary_run_id is unique" do
      submission = described_class.new(run: run)
      first = batchable_bill("SBS-ARM-UNIQ-1", 494)
      second = batchable_bill("SBS-ARM-UNIQ-2", 495)
      accumulate_bill(submission, first)
      accumulate_bill(submission, second)

      submission.submit!

      expect(provisioning_for(first).reload.summary_run_id)
        .not_to eq(provisioning_for(second).reload.summary_run_id)
    end

    it "leaves a row another run already owns alone" do
      submission = described_class.new(run: run)
      bill = batchable_bill("SBS-ARM-OWNED", 496)
      provisioning_for(bill).update_columns(
        generation_status: "generating", summary_run_id: "run:someone-else"
      )
      accumulate_bill(submission, bill.reload)

      submission.submit!

      expect(provisioning_for(bill).reload.summary_run_id).to eq("run:someone-else")
    end
  end

  describe "#verdicts" do
    it "reports a bill whose items are in a batch as awaiting_batch" do
      submission = described_class.new(run: run)
      bill_run = accumulate_bill(submission, batchable_bill("SBS-VERDICT-AWAIT", 500))

      submission.submit!

      expect(submission.verdicts.map(&:outcome)).to eq([described_class::AWAITING_BATCH])
      expect(submission.verdicts.map(&:bill_run)).to eq([bill_run])
    end

    it "reports a bill that earned no item as skipped" do
      submission = described_class.new(run: run)
      accumulate_bill(submission, batchable_bill("SBS-VERDICT-SKIP", 501, text: nil, testimony: false))

      submission.submit!

      expect(submission.verdicts.map(&:outcome)).to eq([described_class::SKIPPED])
    end

    it "counts the items it submitted" do
      submission = described_class.new(run: run)
      accumulate_bill(submission, batchable_bill("SBS-COUNT-BOTH", 502))
      accumulate_bill(submission, batchable_bill("SBS-COUNT-ONE", 503, testimony: false))

      submission.submit!

      expect(submission.item_count).to eq(3)
    end
  end

  def pipeline_run_bill_for(bill)
    create(:pipeline_run_bill, legislation_pipeline_run: run, bill_external_id: bill.external_id)
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Why a row is claimed before the batch is bought]]
  describe "a row another writer already owns" do
    def contended_bill(external_id, days_ago)
      bill = batchable_bill(external_id, days_ago)
      BillLlmProvisioning.where(bill_id: bill.id).update_all(
        generation_status: "generating",
        summary_run_id: SummaryRunMarker.run_claim("some-other-job"),
        updated_at: Time.current
      )
      bill.reload
    end

    it "leaves its items out of the batch rather than buying them twice" do
      submission = described_class.new(run: run)
      accumulate_bill(submission, contended_bill("SBS-CONTENDED", 495))

      submission.submit!

      expect(submitted_chunks).to be_empty
    end

    it "reports it as not claimed, not as awaiting a batch" do
      submission = described_class.new(run: run)
      bill_run = accumulate_bill(submission, contended_bill("SBS-CONTENDED-VERDICT", 496))

      submission.submit!

      outcome = submission.verdicts.find { |verdict| verdict.bill_run == bill_run }&.outcome
      expect(outcome).to eq(described_class::NOT_CLAIMED)
    end

    it "leaves the other writer's claim on the row untouched" do
      submission = described_class.new(run: run)
      bill = contended_bill("SBS-CONTENDED-MARKER", 497)
      accumulate_bill(submission, bill)

      submission.submit!

      expect(provisioning_for(bill).summary_batch_id).to be_nil
    end

    it "still submits the bills in the same chunk that it did claim" do
      submission = described_class.new(run: run)
      accumulate_bill(submission, contended_bill("SBS-CONTENDED-MIXED", 498))
      free = batchable_bill("SBS-FREE-MIXED", 499)
      accumulate_bill(submission, free)

      submission.submit!

      expect(submitted_custom_ids).to all(include(free.id.to_s))
    end

    it "counts only the items it actually bought" do
      submission = described_class.new(run: run)
      accumulate_bill(submission, contended_bill("SBS-CONTENDED-COUNT", 500))
      accumulate_bill(submission, batchable_bill("SBS-FREE-COUNT", 501))

      submission.submit!

      expect(submission.item_count).to eq(2)
    end

    it "has already claimed every row by the time the batch is bought" do
      statuses = []
      allow(Llm::ClaudeBatchService).to receive(:submit) do |items:|
        statuses = BillLlmProvisioning.where(summary_batch_id: nil).pluck(:generation_status)
        submitted_chunks << items
        double(id: "msgbatch_ordering", expires_at: batch_expires_at)
      end
      submission = described_class.new(run: run)
      accumulate_bill(submission, batchable_bill("SBS-ORDER", 502))

      submission.submit!

      expect(statuses).to all(eq("generating"))
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Why a row is claimed before the batch is bought]]
  describe "a row an operator's paste takes after its items were accumulated" do
    def paste_onto_bill!(bill)
      BillLlmProvisioning.where(bill_id: bill.id)
        .update_all(summary_run_id: SummaryRunMarker.operator_paste)
    end

    # SummaryRunArmDecision answers :paste_hand_off only from pending or generating.
    def pending_batchable_bill(external_id, days_ago)
      bill = batchable_bill(external_id, days_ago)
      BillLlmProvisioning.where(bill_id: bill.id).update_all(
        generation_status: "pending", updated_at: Time.current
      )
      bill.reload
    end

    def paste_between_accumulate_and_submit(external_id, days_ago)
      bill = pending_batchable_bill(external_id, days_ago)
      submission = described_class.new(run: run)
      bill_run = accumulate_bill(submission, bill)
      paste_onto_bill!(bill)
      {submission: submission, bill: bill, bill_run: bill_run}
    end

    def paste_while_the_batch_is_bought(external_id, days_ago)
      bill = batchable_bill(external_id, days_ago)
      submission = described_class.new(run: run)
      bill_run = accumulate_bill(submission, bill)
      allow(Llm::ClaudeBatchService).to receive(:submit) do |items:|
        submitted_chunks << items
        paste_onto_bill!(bill)
        double(id: "msgbatch_in_flight", expires_at: batch_expires_at)
      end
      {submission: submission, bill: bill, bill_run: bill_run}
    end

    it "leaves its items out of the batch, since the answer would be discarded" do
      setup = paste_between_accumulate_and_submit("SBS-PASTE-HANDOFF", 510)

      setup[:submission].submit!

      expect(submitted_chunks).to be_empty
    end

    it "leaves the paste marker on the row" do
      setup = paste_between_accumulate_and_submit("SBS-PASTE-MARKER", 511)

      setup[:submission].submit!

      expect(SummaryRunMarker.operator_paste?(provisioning_for(setup[:bill]).summary_run_id)).to be(true)
    end

    it "writes no batch id onto the row" do
      setup = paste_between_accumulate_and_submit("SBS-PASTE-BATCH-ID", 512)

      setup[:submission].submit!

      expect(provisioning_for(setup[:bill]).summary_batch_id).to be_nil
    end

    it "reports it as not claimed, not as awaiting a batch" do
      setup = paste_between_accumulate_and_submit("SBS-PASTE-VERDICT", 513)

      setup[:submission].submit!

      outcome = setup[:submission].verdicts.find { |verdict| verdict.bill_run == setup[:bill_run] }&.outcome
      expect(outcome).to eq(described_class::NOT_CLAIMED)
    end

    it "still submits the bills in the same chunk that it did claim" do
      setup = paste_between_accumulate_and_submit("SBS-PASTE-MIXED", 514)
      free = batchable_bill("SBS-PASTE-FREE", 515)
      accumulate_bill(setup[:submission], free)

      setup[:submission].submit!

      expect(submitted_custom_ids).to all(include(free.id.to_s))
    end

    it "leaves a paste that lands while the batch is being bought in place" do
      setup = paste_while_the_batch_is_bought("SBS-PASTE-IN-FLIGHT", 516)

      setup[:submission].submit!

      expect(SummaryRunMarker.operator_paste?(provisioning_for(setup[:bill]).summary_run_id)).to be(true)
    end

    it "writes no batch id over a paste that lands while the batch is being bought" do
      setup = paste_while_the_batch_is_bought("SBS-PASTE-IN-FLIGHT-ID", 517)

      setup[:submission].submit!

      expect(provisioning_for(setup[:bill]).summary_batch_id).to be_nil
    end
  end
end
