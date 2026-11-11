# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Batch summarisation#A batch is read back exactly once]]
RSpec.describe SummaryBatchIngest do
  let(:sway_locale) { SwayLocale.find_by(city: "baltimore") || create(:sway_locale, :baltimore) }
  let(:run) do
    create(:legislation_pipeline_run, status: "awaiting_summary_batch",
      current_stage: "summarize", started_at: 1.minute.ago)
  end
  let(:batch) do
    create(:pipeline_run_summary_batch, legislation_pipeline_run: run,
      batch_id: "msgbatch_a", item_count: 2)
  end
  let(:retry_expires_at) { 23.hours.from_now.change(usec: 0) }

  before do
    allow(Llm::ClaudeBatchService).to receive(:submit)
      .and_return(double(id: "msgbatch_retry", expires_at: retry_expires_at))
  end

  def batched_bill(external_id, days_ago, on: batch, text: "Section 1.", testimony: true)
    bill = create(:bill, external_id: external_id, sway_locale: sway_locale,
      extracted_text: text, scheduled_release_date_utc: days_ago.days.ago)
    traits = testimony ? [:with_testimony] : []
    provisioning = create(:bill_llm_provisioning, :generating, *traits, bill: bill)
    provisioning.update_columns(
      summary_run_id: SummaryRunMarker.run_claim(
        SummaryRunMarker.batch_run_id(batch_id: on.batch_id, bill_id: bill.id)
      ),
      summary_batch_id: on.batch_id,
      summary_batch_expires_at: on.expires_at,
      summary_batch_testimony_digest: provisioning.testimony_digest
    )
    create(:pipeline_run_bill, :running, legislation_pipeline_run: run,
      bill_external_id: external_id,
      stage_results: {"summarize" => {"status" => "awaiting_batch", "at" => Time.current.iso8601}})
    bill.reload
  end

  def provisioning_for(bill) = BillLlmProvisioning.find_by!(bill_id: bill.id)

  def bill_run_for(bill) = run.pipeline_run_bills.find_by!(bill_external_id: bill.external_id)

  def cid(bill, answer_type) = SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: answer_type)

  def ended_status(succeeded: 0, errored: 0, canceled: 0, expired: 0)
    double(
      processing_status: "ended",
      request_counts: double(
        succeeded: succeeded, errored: errored, canceled: canceled, expired: expired
      )
    )
  end

  def ok_summary(bill)
    Llm::ClaudeBatchService::Result.new(
      custom_id: cid(bill, SummaryBatchItem::SUMMARY),
      value: {"summary_markdown" => "A short summary.", "full_breakdown_markdown" => "## Section 1"},
      error: nil, usage: nil, model: "claude-sonnet-5-20260101"
    )
  end

  def ok_positions(bill)
    Llm::ClaudeBatchService::Result.new(
      custom_id: cid(bill, SummaryBatchItem::POSITIONS),
      value: {"draft_org_positions" => [{"org_name" => "Test Org", "stance" => "support", "summary" => "Yes"}]},
      error: nil, usage: nil, model: "claude-sonnet-5-20260101"
    )
  end

  def failed_item(bill, answer_type, error = Llm::TransportError.new("claude transport: api_error overloaded"))
    Llm::ClaudeBatchService::Result.new(
      custom_id: cid(bill, answer_type), value: nil, error: error, usage: nil, model: nil
    )
  end

  def ingest!(results, status = nil, on: batch)
    keyed = results.index_by(&:custom_id)
    allow(Llm::ClaudeBatchService).to receive(:status)
      .with(batch_id: on.batch_id)
      .and_return(status || ended_status(succeeded: keyed.count { |_k, r| r.error.nil? }))
    allow(Llm::ClaudeBatchService).to receive(:results).and_return(keyed)
    described_class.call(run: run.reload)
  end

  def bill_existence_queries
    queries = [] #: Array[String]
    subscriber = ->(_name, _start, _finish, _id, payload) do
      sql = payload[:sql].to_s
      if sql.match?(/\ASELECT 1 AS one FROM "bills" WHERE .*"bills"\."id" =/) &&
          caller_locations.any? { |location| location.path.to_s.end_with?("/summary_batch_ingest.rb") } &&
          caller_locations.none? { |location| location.path.to_s.end_with?("/summary_batch_result_persister.rb") }
        queries << sql
      end
    end
    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      ActiveRecord::Base.uncached { yield }
    end
    queries
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Successful readback query budget]]
  it "persists successful answers without standalone bill existence queries" do
    bill = batched_bill("SBI-QUERY-OK", 810)
    results = [ok_summary(bill), ok_positions(bill)]

    queries = bill_existence_queries { ingest!(results) }

    expect(provisioning_for(bill).llm_summary).to eq("A short summary.")
    expect(provisioning_for(bill).draft_org_positions.first["org_name"]).to eq("Test Org")
    expect(provisioning_for(bill).generation_status).to eq("completed")
    expect(bill_run_for(bill).status).to eq("succeeded")
    expect(batch.reload.ingested_at).to be_present
    expect(run.reload.status).to eq("succeeded")
    expect(Llm::ClaudeBatchService).not_to have_received(:submit)
    expect(queries).to be_empty
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Retry readback query budget]]
  it "retries a transport failure without standalone bill existence queries" do
    bill = batched_bill("SBI-QUERY-RETRY", 811)
    results = [ok_summary(bill), failed_item(bill, SummaryBatchItem::POSITIONS)]
    status = ended_status(succeeded: 1, errored: 1)

    queries = bill_existence_queries { ingest!(results, status) }

    expect(provisioning_for(bill).llm_summary).to eq("A short summary.")
    expect(provisioning_for(bill).draft_org_positions).to be_blank
    expect(provisioning_for(bill).generation_status).to eq("generating")
    expect(provisioning_for(bill).summary_batch_id).to eq("msgbatch_retry")
    expect(batch.reload.ingested_at).to be_present
    retry_batch = run.pipeline_run_summary_batches.find_by!(batch_id: "msgbatch_retry")
    expect(retry_batch.attempt).to eq(2)
    expect(retry_batch.item_count).to eq(1)
    expect(bill_run_for(bill).stage_results.dig("summarize", "status")).to eq("awaiting_batch")
    expect(run.reload.status).to eq("awaiting_summary_batch")
    expect(Llm::ClaudeBatchService).to have_received(:submit) { |items:|
      expect(items.map(&:custom_id)).to eq([cid(bill, SummaryBatchItem::POSITIONS)])
    }
    expect(queries).to be_empty
  end

  # @lat: [[bill-session-archiving-tests#Bill session archive tests#Batch ingestion skips archives]]
  it "settles live batch siblings without querying or changing archived bills" do
    archived = batched_bill("SBI-ARCHIVE", 810)
    live = batched_bill("SBI-LIVE", 811)
    archived_provisioning = provisioning_for(archived)
    archived.update!(archived_at: Time.current)

    ingest!([ok_summary(archived), ok_positions(archived), ok_summary(live), ok_positions(live)])

    expect(batch.reload.ingested_at).to be_present
    expect(provisioning_for(live).generation_status).to eq("completed")
    expect(archived_provisioning.reload.llm_summary).to be_nil
    expect(run.reload.status).to eq("succeeded")
    expect(Llm::ClaudeBatchService).not_to have_received(:submit)
  end

  describe "a batch that has not ended" do
    it "leaves it un-ingested for the next tick" do
      batched_bill("SBI-PENDING", 800)
      allow(Llm::ClaudeBatchService).to receive(:status)
        .and_return(double(processing_status: "in_progress"))
      allow(Llm::ClaudeBatchService).to receive(:results)

      described_class.call(run: run.reload)

      expect(batch.reload.ingested_at).to be_nil
    end

    it "never reads its results" do
      batched_bill("SBI-PENDING-2", 801)
      allow(Llm::ClaudeBatchService).to receive(:status)
        .and_return(double(processing_status: "in_progress"))
      allow(Llm::ClaudeBatchService).to receive(:results)

      described_class.call(run: run.reload)

      expect(Llm::ClaudeBatchService).not_to have_received(:results)
    end

    it "leaves the run waiting" do
      batched_bill("SBI-PENDING-3", 802)
      allow(Llm::ClaudeBatchService).to receive(:status)
        .and_return(double(processing_status: "in_progress"))
      allow(Llm::ClaudeBatchService).to receive(:results)

      described_class.call(run: run.reload)

      expect(run.reload.status).to eq("awaiting_summary_batch")
    end
  end

  describe "a batch whose items all succeeded" do
    it "writes the summary onto the row" do
      bill = batched_bill("SBI-OK", 810)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(provisioning_for(bill).llm_summary).to eq("A short summary.")
    end

    it "writes the drafts onto the row" do
      bill = batched_bill("SBI-OK-POS", 811)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(provisioning_for(bill).draft_org_positions.first["org_name"]).to eq("Test Org")
    end

    it "settles the row completed" do
      bill = batched_bill("SBI-OK-SETTLE", 812)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(provisioning_for(bill).generation_status).to eq("completed")
    end

    it "rewrites the bill's summarize stage from awaiting_batch to succeeded" do
      bill = batched_bill("SBI-OK-STAGE", 813)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(bill_run_for(bill).stage_results.dig("summarize", "status")).to eq("succeeded")
    end

    it "marks the run's bill row succeeded" do
      bill = batched_bill("SBI-OK-BILLRUN", 814)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(bill_run_for(bill).status).to eq("succeeded")
    end

    it "recomputes the bill's score, because a paid answer landed" do
      bill = batched_bill("SBI-OK-SCORE", 815)

      expect { ingest!([ok_summary(bill), ok_positions(bill)]) }
        .to have_enqueued_job(RecomputeBillInterestingScoreJob).with(bill.id)
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#A batch is read back exactly once]]
  describe "reading a batch back exactly once" do
    it "stamps ingested_at" do
      bill = batched_bill("SBI-ONCE", 820)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(batch.reload.ingested_at).to be_present
    end

    it "does not read an already-ingested batch a second time" do
      bill = batched_bill("SBI-ONCE-2", 821)
      ingest!([ok_summary(bill), ok_positions(bill)])
      reads = 0
      allow(Llm::ClaudeBatchService).to receive(:results) { reads += 1 }

      described_class.call(run: run.reload)

      expect(reads).to eq(0)
    end

    it "builds the read-back map from the database, not from anything the submission kept" do
      bill = batched_bill("SBI-MAP", 822)
      captured = {} #: Hash[String, Llm::ClaudeBatchService::Item]
      allow(Llm::ClaudeBatchService).to receive(:status).and_return(ended_status(succeeded: 2))
      allow(Llm::ClaudeBatchService).to receive(:results) do |batch_id:, items_by_custom_id:|
        captured = items_by_custom_id
        {}
      end

      described_class.call(run: run.reload)

      expect(captured.keys).to contain_exactly(
        cid(bill, SummaryBatchItem::SUMMARY), cid(bill, SummaryBatchItem::POSITIONS)
      )
    end

    it "never rebuilds a prompt to read a result back" do
      batched_bill("SBI-NO-PROMPT", 823)
      captured = {} #: Hash[String, Llm::ClaudeBatchService::Item]
      allow(Llm::ClaudeBatchService).to receive(:status).and_return(ended_status)
      allow(Llm::ClaudeBatchService).to receive(:results) do |batch_id:, items_by_custom_id:|
        captured = items_by_custom_id
        {}
      end

      described_class.call(run: run.reload)

      expect(captured.each_value.map { |item| item.prompt.user_message }.uniq).to eq([""])
    end

    it "records the batch's own per-outcome counts" do
      bill = batched_bill("SBI-COUNTS", 824)

      ingest!([ok_summary(bill), failed_item(bill, SummaryBatchItem::POSITIONS)],
        ended_status(succeeded: 1, errored: 1))

      expect(batch.reload.attributes.values_at(
        "succeeded_count", "errored_count", "canceled_count", "expired_count"
      )).to eq([1, 1, 0, 0])
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#Where the per-outcome counts come from]]
    it "counts what it could read when the batch reports no per-outcome counts" do
      bill = batched_bill("SBI-COUNTS-NONE", 825)

      ingest!([ok_summary(bill), failed_item(bill, SummaryBatchItem::POSITIONS)],
        double(processing_status: "ended"))

      expect(batch.reload.attributes.values_at(
        "succeeded_count", "errored_count", "canceled_count", "expired_count"
      )).to eq([1, 1, 0, 0])
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#Where the per-outcome counts come from]]
    it "counts a reported success whose payload did not validate as an error" do
      bill = batched_bill("SBI-COUNTS-UNUSABLE", 826)
      schema_error = Llm::SchemaError.new("claude-batch returned invalid JSON")

      ingest!([ok_summary(bill), failed_item(bill, SummaryBatchItem::POSITIONS, schema_error)],
        ended_status(succeeded: 2))

      expect(batch.reload.attributes.values_at(
        "succeeded_count", "errored_count", "canceled_count", "expired_count"
      )).to eq([1, 1, 0, 0])
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Why an unknown custom_id is an error, not an exception]]
  describe "a custom_id no bill answers any more" do
    it "keeps the rest of the batch" do
      bill = batched_bill("SBI-UNKNOWN", 830)
      stray = Llm::ClaudeBatchService::Result.new(
        custom_id: "bill__99999999__summary", value: nil,
        error: Llm::TransportError.new("claude transport: unknown custom_id"), usage: nil, model: nil
      )
      allow(SwayLogging).to receive(:warn)

      ingest!([ok_summary(bill), ok_positions(bill), stray])

      expect(provisioning_for(bill).generation_status).to eq("completed")
    end

    it "says so, since there is nothing to write and nothing to retry" do
      bill = batched_bill("SBI-UNKNOWN-2", 831)
      stray = Llm::ClaudeBatchService::Result.new(
        custom_id: "bill__99999999__summary", value: nil,
        error: Llm::TransportError.new("claude transport: unknown custom_id"), usage: nil, model: nil
      )
      allow(SwayLogging).to receive(:warn)

      ingest!([ok_summary(bill), stray])

      expect(SwayLogging).to have_received(:warn).with(
        "summary_batch_ingest.unknown_custom_id", hash_including(custom_id: "bill__99999999__summary")
      )
    end

    it "buys no retry batch for it" do
      bill = batched_bill("SBI-UNKNOWN-3", 832)
      stray = Llm::ClaudeBatchService::Result.new(
        custom_id: "bill__99999999__positions", value: nil,
        error: Llm::TransportError.new("claude transport: unknown custom_id"), usage: nil, model: nil
      )
      allow(SwayLogging).to receive(:warn)

      ingest!([ok_summary(bill), ok_positions(bill), stray])

      expect(Llm::ClaudeBatchService).not_to have_received(:submit)
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#A failed item is retried once, as a batch]]
  describe "an item that failed on the first attempt" do
    it "buys a retry as a new batch rather than a synchronous call" do
      bill = batched_bill("SBI-RETRY", 840)

      ingest!([ok_summary(bill), failed_item(bill, SummaryBatchItem::POSITIONS)],
        ended_status(succeeded: 1, errored: 1))

      expect(Llm::ClaudeBatchService).to have_received(:submit)
    end

    it "records the retry as the run's second attempt" do
      bill = batched_bill("SBI-RETRY-ATTEMPT", 841)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(run.pipeline_run_summary_batches.find_by(batch_id: "msgbatch_retry").attempt).to eq(2)
    end

    it "records how many items the retry carries" do
      bill = batched_bill("SBI-RETRY-COUNT", 842)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY),
        failed_item(bill, SummaryBatchItem::POSITIONS)], ended_status(errored: 2))

      expect(run.pipeline_run_summary_batches.find_by(batch_id: "msgbatch_retry").item_count).to eq(2)
    end

    it "rebuilds only the items that failed" do
      bill = batched_bill("SBI-RETRY-ITEMS", 843)

      ingest!([ok_summary(bill), failed_item(bill, SummaryBatchItem::POSITIONS)],
        ended_status(succeeded: 1, errored: 1))

      expect(Llm::ClaudeBatchService).to have_received(:submit) { |items:|
        expect(items.map(&:custom_id)).to eq([cid(bill, SummaryBatchItem::POSITIONS)])
      }
    end

    it "moves the row's stamp onto the retry batch" do
      bill = batched_bill("SBI-RETRY-STAMP", 844)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(provisioning_for(bill).summary_batch_id).to eq("msgbatch_retry")
    end

    it "moves the exemption from the abandoned sweep onto the retry's expiry" do
      bill = batched_bill("SBI-RETRY-EXPIRY", 845)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(provisioning_for(bill).summary_batch_expires_at).to be_within(1.second).of(retry_expires_at)
    end

    it "re-stamps the claim so the retry's results can be recognized" do
      bill = batched_bill("SBI-RETRY-CLAIM", 846)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(provisioning_for(bill).summary_run_id).to eq(
        SummaryRunMarker.run_claim(
          SummaryRunMarker.batch_run_id(batch_id: "msgbatch_retry", bill_id: bill.id)
        )
      )
    end

    it "leaves the row generating, because the retry has not answered yet" do
      bill = batched_bill("SBI-RETRY-GENERATING", 847)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(provisioning_for(bill).generation_status).to eq("generating")
    end

    it "leaves the bill's stage result awaiting_batch" do
      bill = batched_bill("SBI-RETRY-STAGE", 848)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(bill_run_for(bill).stage_results.dig("summarize", "status")).to eq("awaiting_batch")
    end

    it "leaves the run waiting on the retry" do
      bill = batched_bill("SBI-RETRY-RUN", 849)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(run.reload.status).to eq("awaiting_summary_batch")
    end

    it "keeps a summary that succeeded even though the other half is being retried" do
      bill = batched_bill("SBI-RETRY-KEEP", 850)

      ingest!([ok_summary(bill), failed_item(bill, SummaryBatchItem::POSITIONS)],
        ended_status(succeeded: 1, errored: 1))

      expect(provisioning_for(bill).llm_summary).to eq("A short summary.")
    end

    it "retries a canceled item the same way it retries an errored one" do
      bill = batched_bill("SBI-RETRY-CANCELED", 851)
      canceled = Llm::TransportError.new("claude transport: item canceled")

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY, canceled)], ended_status(canceled: 1))

      expect(Llm::ClaudeBatchService).to have_received(:submit)
    end

    it "retries an expired item, which says nothing about the request" do
      bill = batched_bill("SBI-RETRY-EXPIRED", 852)
      expired = Llm::TransportError.new("claude transport: item expired (batch exceeded 24h)")

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY, expired)], ended_status(expired: 1))

      expect(Llm::ClaudeBatchService).to have_received(:submit)
    end

    it "settles the row failed when the retry batch cannot be bought" do
      bill = batched_bill("SBI-RETRY-REFUSED", 853)
      allow(Llm::ClaudeBatchService).to receive(:submit).and_raise(Llm::TransportError, "refused")
      allow(SwayLogging).to receive(:log_exception)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(provisioning_for(bill).generation_status).to eq("failed")
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#The read is recorded before the retry is bought]]
    it "stamps the read before it buys the retry" do
      bill = batched_bill("SBI-RETRY-ORDER", 854)
      stamped = nil #: ActiveSupport::TimeWithZone?
      allow(Llm::ClaudeBatchService).to receive(:submit) do
        stamped = batch.reload.ingested_at
        double(id: "msgbatch_retry", expires_at: retry_expires_at)
      end

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(stamped).to be_present
    end

    it "settles a bill an operator pasted onto while the retry was being bought" do
      bill = batched_bill("SBI-RETRY-PASTE-RACE", 855)
      allow(SwayLogging).to receive(:warn)
      allow(Llm::ClaudeBatchService).to receive(:submit) do
        provisioning_for(bill).update_columns(summary_run_id: SummaryRunMarker.operator_paste)
        double(id: "msgbatch_retry", expires_at: retry_expires_at)
      end

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(bill_run_for(bill).stage_results.dig("summarize", "status")).to eq("succeeded")
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#A failed item is retried once, as a batch]]
  describe "an item that failed again on the retry" do
    let(:batch) do
      create(:pipeline_run_summary_batch, legislation_pipeline_run: run,
        batch_id: "msgbatch_a", item_count: 2, attempt: PipelineRunSummaryBatch::MAX_ATTEMPTS)
    end

    it "buys no third attempt" do
      bill = batched_bill("SBI-FINAL", 860)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(Llm::ClaudeBatchService).not_to have_received(:submit)
    end

    it "settles the row failed" do
      bill = batched_bill("SBI-FINAL-2", 861)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(provisioning_for(bill).generation_status).to eq("failed")
    end

    it "puts the reported reason on the row" do
      bill = batched_bill("SBI-FINAL-3", 862)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(provisioning_for(bill).generation_error).to include("api_error overloaded")
    end

    it "caps the reason at the row's error budget" do
      bill = batched_bill("SBI-FINAL-LONG", 863)
      long = Llm::TransportError.new("claude transport: #{"x" * 2000}")

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY, long)], ended_status(errored: 1))

      expect(provisioning_for(bill).generation_error.to_s.length)
        .to eq(GenerateBillSummaryJob::MAX_GENERATION_ERROR_LENGTH)
    end

    it "records the bill's summarize stage as failed" do
      bill = batched_bill("SBI-FINAL-STAGE", 864)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(bill_run_for(bill).stage_results.dig("summarize", "status")).to eq("failed")
    end

    it "marks the run's bill row failed" do
      bill = batched_bill("SBI-FINAL-BILLRUN", 865)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(bill_run_for(bill).status).to eq("failed")
    end

    it "writes a provider failure to the activity log through the existing per-bill event" do
      bill = batched_bill("SBI-FINAL-LOG", 866)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(PipelineActivityLogEntry.where(event_type: "llm_provider_error")).to be_present
    end

    it "writes an unreadable reply to the activity log as a parse failure" do
      bill = batched_bill("SBI-FINAL-PARSE", 867)
      schema_error = Llm::SchemaError.new("claude-batch returned invalid JSON")

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY, schema_error)], ended_status(succeeded: 1))

      expect(PipelineActivityLogEntry.where(event_type: "llm_json_parse_failure")).to be_present
    end

    it "keeps a bill whose items succeeded, even beside one whose failed" do
      good = batched_bill("SBI-FINAL-GOOD", 868)
      bad = batched_bill("SBI-FINAL-BAD", 869)

      ingest!([ok_summary(good), ok_positions(good), failed_item(bad, SummaryBatchItem::SUMMARY),
        failed_item(bad, SummaryBatchItem::POSITIONS)], ended_status(succeeded: 2, errored: 2))

      expect(provisioning_for(good).generation_status).to eq("completed")
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#What settles a bill once its items are accounted for]]
    it "settles a bill whose summary landed and whose positions failed as completed" do
      bill = batched_bill("SBI-FINAL-PARTIAL", 870)

      ingest!([ok_summary(bill), failed_item(bill, SummaryBatchItem::POSITIONS)],
        ended_status(succeeded: 1, errored: 1))

      expect(provisioning_for(bill).generation_status).to eq("completed")
    end

    it "records that partial failure in the shape the synchronous path uses" do
      bill = batched_bill("SBI-FINAL-PARTIAL-2", 871)

      ingest!([ok_summary(bill), failed_item(bill, SummaryBatchItem::POSITIONS)],
        ended_status(succeeded: 1, errored: 1))

      expect(provisioning_for(bill).generation_error)
        .to start_with("positions call failed (the summary is valid): ")
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#What settles a bill once its items are accounted for]]
    it "settles a row an earlier attempt half wrote as completed" do
      bill = batched_bill("SBI-FINAL-HALF", 872)
      provisioning_for(bill).update_columns(llm_summary: "an earlier attempt wrote this")

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY),
        failed_item(bill, SummaryBatchItem::POSITIONS)], ended_status(errored: 2))

      expect(provisioning_for(bill).generation_status).to eq("completed")
    end

    it "keeps the reported reason on the row it settled completed" do
      bill = batched_bill("SBI-FINAL-HALF-2", 873)
      provisioning_for(bill).update_columns(llm_summary: "an earlier attempt wrote this")

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY),
        failed_item(bill, SummaryBatchItem::POSITIONS)], ended_status(errored: 2))

      expect(provisioning_for(bill).generation_error)
        .to include("positions call failed (the summary is valid): ")
    end

    it "records the summarize stage as not run when the row moved on first" do
      bill = batched_bill("SBI-FINAL-MOVED", 874)
      provisioning_for(bill).update_columns(generation_status: "completed")

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(bill_run_for(bill).stage_results.dig("summarize", "reason"))
        .to eq("row_moved_before_the_failure_settled")
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#What a batch that cannot be read back settles as]]
  describe "a batch that cannot be read back" do
    it "leaves a live batch for the next tick rather than marking it ingested" do
      batched_bill("SBI-UNREAD-LIVE", 880)
      allow(Llm::ClaudeBatchService).to receive(:status).and_return(ended_status)
      allow(Llm::ClaudeBatchService).to receive(:results).and_raise(Llm::TransportError, "429 rate_limit")
      allow(SwayLogging).to receive(:warn)

      described_class.call(run: run.reload)

      expect(batch.reload.ingested_at).to be_nil
    end

    it "settles an expired batch rather than leaving the run waiting forever" do
      batched_bill("SBI-UNREAD-EXPIRED", 881)
      batch.update_columns(expires_at: 1.minute.ago)
      allow(Llm::ClaudeBatchService).to receive(:status).and_return(ended_status)
      allow(Llm::ClaudeBatchService).to receive(:results).and_raise(Llm::TransportError, "gone")
      allow(SwayLogging).to receive(:warn)

      described_class.call(run: run.reload)

      expect(batch.reload.ingested_at).to be_present
    end

    it "counts every item it submitted as expired" do
      batched_bill("SBI-UNREAD-COUNT", 882)
      batch.update_columns(expires_at: 1.minute.ago)
      allow(Llm::ClaudeBatchService).to receive(:status).and_return(ended_status)
      allow(Llm::ClaudeBatchService).to receive(:results).and_raise(Llm::TransportError, "gone")
      allow(SwayLogging).to receive(:warn)

      described_class.call(run: run.reload)

      expect(batch.reload.expired_count).to eq(2)
    end

    it "retries what the rows still owe" do
      batched_bill("SBI-UNREAD-RETRY", 883)
      batch.update_columns(expires_at: 1.minute.ago)
      allow(Llm::ClaudeBatchService).to receive(:status).and_return(ended_status)
      allow(Llm::ClaudeBatchService).to receive(:results).and_raise(Llm::TransportError, "gone")
      allow(SwayLogging).to receive(:warn)

      described_class.call(run: run.reload)

      expect(Llm::ClaudeBatchService).to have_received(:submit)
    end

    it "does not buy again a half an earlier attempt already persisted" do
      bill = batched_bill("SBI-UNREAD-HALF", 884)
      provisioning_for(bill).update_columns(llm_summary: "already bought")
      batch.update_columns(expires_at: 1.minute.ago, attempt: PipelineRunSummaryBatch::MAX_ATTEMPTS)
      allow(Llm::ClaudeBatchService).to receive(:status).and_return(ended_status)
      allow(Llm::ClaudeBatchService).to receive(:results).and_raise(Llm::TransportError, "gone")
      allow(SwayLogging).to receive(:warn)

      described_class.call(run: run.reload)

      expect(provisioning_for(bill).generation_error).to start_with("positions call failed (the summary is valid): ")
    end

    it "settles an expired batch whose read raised something other than a transport error" do
      batched_bill("SBI-UNREAD-ARGUMENT", 885)
      batch.update_columns(expires_at: 1.minute.ago)
      allow(Llm::ClaudeBatchService).to receive(:status).and_return(ended_status)
      allow(Llm::ClaudeBatchService).to receive(:results).and_raise(ArgumentError, "malformed page cursor")
      allow(SwayLogging).to receive(:warn)

      described_class.call(run: run.reload)

      expect(batch.reload.ingested_at).to be_present
    end

    it "settles a bill an earlier attempt already answered in full" do
      bill = batched_bill("SBI-UNREAD-WHOLE", 886)
      provisioning_for(bill).update_columns(
        llm_summary: "an earlier attempt wrote this",
        draft_org_positions: [{"org_name" => "Test Org", "stance" => "support", "summary" => "Yes"}]
      )
      batch.update_columns(expires_at: 1.minute.ago)
      allow(Llm::ClaudeBatchService).to receive(:status).and_return(ended_status)
      allow(Llm::ClaudeBatchService).to receive(:results).and_raise(Llm::TransportError, "gone")
      allow(SwayLogging).to receive(:warn)

      described_class.call(run: run.reload)

      expect(provisioning_for(bill).generation_status).to eq("completed")
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Why the waiting state loops back to summarizing]]
  describe "finishing the run" do
    it "finalizes the run once every batch is ingested" do
      bill = batched_bill("SBI-FINISH", 890)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(run.reload.status).to eq("succeeded")
    end

    it "lands the run partial when a bill failed outright" do
      bill = batched_bill("SBI-FINISH-PARTIAL", 891)
      batch.update_columns(attempt: PipelineRunSummaryBatch::MAX_ATTEMPTS)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY),
        failed_item(bill, SummaryBatchItem::POSITIONS)], ended_status(errored: 2))

      expect(run.reload.status).to eq("partial")
    end

    it "waits while another batch of the same run is still pending" do
      other = create(:pipeline_run_summary_batch, legislation_pipeline_run: run,
        batch_id: "msgbatch_b", item_count: 1)
      bill = batched_bill("SBI-FINISH-TWO", 892)
      allow(Llm::ClaudeBatchService).to receive(:status)
        .with(batch_id: batch.batch_id).and_return(ended_status(succeeded: 2))
      allow(Llm::ClaudeBatchService).to receive(:status)
        .with(batch_id: other.batch_id).and_return(double(processing_status: "in_progress"))
      allow(Llm::ClaudeBatchService).to receive(:results)
        .and_return([ok_summary(bill), ok_positions(bill)].index_by(&:custom_id))

      described_class.call(run: run.reload)

      expect(run.reload.status).to eq("awaiting_summary_batch")
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#What settles a bill once its items are accounted for]]
  describe "an operator paste that landed while the batch was in flight" do
    it "settles the row onto the pasted body rather than the batch's answer" do
      bill = batched_bill("SBI-PASTE", 900)
      provisioning_for(bill).update_columns(
        summary_run_id: SummaryRunMarker.operator_paste, llm_summary: "What a person wrote"
      )
      allow(SwayLogging).to receive(:warn)

      ingest!([ok_summary(bill), ok_positions(bill)], ended_status(succeeded: 2))

      expect(provisioning_for(bill).llm_summary).to eq("What a person wrote")
    end

    it "still settles the bill's stage as succeeded" do
      bill = batched_bill("SBI-PASTE-2", 901)
      provisioning_for(bill).update_columns(
        summary_run_id: SummaryRunMarker.operator_paste, llm_summary: "What a person wrote"
      )
      allow(SwayLogging).to receive(:warn)

      ingest!([ok_summary(bill), ok_positions(bill)], ended_status(succeeded: 2))

      expect(bill_run_for(bill).stage_results.dig("summarize", "status")).to eq("succeeded")
    end

    it "writes the paste stand-down the synchronous job writes" do
      bill = batched_bill("SBI-PASTE-3", 902)
      provisioning_for(bill).update_columns(
        summary_run_id: SummaryRunMarker.operator_paste, llm_summary: "What a person wrote"
      )
      allow(SwayLogging).to receive(:warn)

      ingest!([ok_summary(bill), ok_positions(bill)], ended_status(succeeded: 2))

      expect(PipelineActivityLogEntry.where(event_type: "summary_stood_down_for_paste")).to be_present
    end

    it "leaves the pasted row generating rather than flipping it failed" do
      bill = batched_bill("SBI-PASTE-FAIL", 903)
      provisioning_for(bill).update_columns(summary_run_id: SummaryRunMarker.operator_paste)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(provisioning_for(bill).generation_status).to eq("generating")
    end

    it "writes no provider reason over the pasted row" do
      bill = batched_bill("SBI-PASTE-FAIL-2", 904)
      provisioning_for(bill).update_columns(summary_run_id: SummaryRunMarker.operator_paste)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(provisioning_for(bill).generation_error).to be_nil
    end

    it "records the bill's summarize stage as succeeded, not failed" do
      bill = batched_bill("SBI-PASTE-FAIL-3", 905)
      provisioning_for(bill).update_columns(summary_run_id: SummaryRunMarker.operator_paste)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(bill_run_for(bill).stage_results.dig("summarize", "status")).to eq("succeeded")
    end

    it "writes no partial-failure note over the pasted body" do
      bill = batched_bill("SBI-PASTE-PARTIAL", 906)
      provisioning_for(bill).update_columns(
        summary_run_id: SummaryRunMarker.operator_paste, llm_summary: "What a person wrote"
      )
      batch.update_columns(attempt: PipelineRunSummaryBatch::MAX_ATTEMPTS)
      allow(SwayLogging).to receive(:warn)

      ingest!([ok_summary(bill), failed_item(bill, SummaryBatchItem::POSITIONS)],
        ended_status(succeeded: 1, errored: 1))

      expect(provisioning_for(bill).generation_error).to be_nil
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#A retry asks eligibility again before it buys]]
  describe "what a retry declines to buy again" do
    it "buys nothing for a row an operator pasted onto" do
      bill = batched_bill("SBI-NO-REBUY-PASTE", 910)
      provisioning_for(bill).update_columns(summary_run_id: SummaryRunMarker.operator_paste)

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(Llm::ClaudeBatchService).not_to have_received(:submit)
    end

    it "buys no summary for a row that already holds one" do
      bill = batched_bill("SBI-NO-REBUY-SUMMARY", 911)
      provisioning_for(bill).update_columns(llm_summary: "an earlier attempt wrote this")

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(Llm::ClaudeBatchService).not_to have_received(:submit)
    end

    it "buys no positions for a row that already holds drafts" do
      bill = batched_bill("SBI-NO-REBUY-POSITIONS", 912)
      provisioning_for(bill).update_columns(
        draft_org_positions: [{"org_name" => "Test Org", "stance" => "support", "summary" => "Yes"}]
      )

      ingest!([failed_item(bill, SummaryBatchItem::POSITIONS)], ended_status(errored: 1))

      expect(Llm::ClaudeBatchService).not_to have_received(:submit)
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#What settles a bill once its items are accounted for]]
  describe "a row deleted while the batch was in flight" do
    it "records the bill's summarize stage as not run" do
      bill = batched_bill("SBI-VANISHED", 920)
      allow(SummaryBatchResultPersister).to receive(:call).and_return(:vanished)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(bill_run_for(bill).stage_results.dig("summarize", "status")).to eq("not_run")
    end

    it "says the row was gone before the answer landed" do
      bill = batched_bill("SBI-VANISHED-2", 921)
      allow(SummaryBatchResultPersister).to receive(:call).and_return(:vanished)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(bill_run_for(bill).stage_results.dig("summarize", "reason"))
        .to eq("row_gone_before_the_answer_landed")
    end

    it "settles nothing completed for it" do
      bill = batched_bill("SBI-VANISHED-3", 922)
      allow(SummaryBatchResultPersister).to receive(:call).and_return(:vanished)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(provisioning_for(bill).generation_status).to eq("generating")
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#What settles a bill once its items are accounted for]]
  describe "an answer that cannot be written" do
    it "lands the rest of the chunk" do
      bad = batched_bill("SBI-PERSIST-RAISE-BAD", 930)
      good = batched_bill("SBI-PERSIST-RAISE-GOOD", 931)
      batch.update_columns(attempt: PipelineRunSummaryBatch::MAX_ATTEMPTS)
      allow(SwayLogging).to receive(:log_exception)
      allow(SummaryBatchResultPersister).to receive(:call).and_wrap_original do |original, **kwargs|
        raise Llm::TransportError, "write refused" if kwargs[:bill].id == bad.id

        original.call(**kwargs)
      end

      ingest!([ok_summary(bad), ok_positions(bad), ok_summary(good), ok_positions(good)],
        ended_status(succeeded: 4))

      expect(provisioning_for(good).generation_status).to eq("completed")
    end

    it "says which answer could not be written" do
      bad = batched_bill("SBI-PERSIST-RAISE-BAD-2", 932)
      batch.update_columns(attempt: PipelineRunSummaryBatch::MAX_ATTEMPTS)
      allow(SwayLogging).to receive(:log_exception)
      allow(SummaryBatchResultPersister).to receive(:call).and_wrap_original do |original, **kwargs|
        raise Llm::TransportError, "write refused" if kwargs[:bill].id == bad.id

        original.call(**kwargs)
      end

      ingest!([ok_summary(bad), ok_positions(bad)], ended_status(succeeded: 2))

      expect(SwayLogging).to have_received(:log_exception).with(
        "summary_batch_ingest.persist_failed",
        hash_including(bill_id: bad.id, answer_type: SummaryBatchItem::SUMMARY)
      )
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#What settles a bill once its items are accounted for]]
  describe "a bill whose settle raises" do
    it "settles the rest of the batch" do
      bad = batched_bill("SBI-SETTLE-RAISE-BAD", 940)
      good = batched_bill("SBI-SETTLE-RAISE-GOOD", 941)
      allow(SwayLogging).to receive(:log_exception)
      allow(SummaryRunSettle).to receive(:completed!).and_wrap_original do |original, bill, provisioning, **kwargs|
        raise Llm::TransportError, "settle refused" if bill.id == bad.id

        original.call(bill, provisioning, **kwargs)
      end

      ingest!([ok_summary(bad), ok_positions(bad), ok_summary(good), ok_positions(good)],
        ended_status(succeeded: 4))

      expect(provisioning_for(good).generation_status).to eq("completed")
    end

    it "says which bill was left for the reclaim sweep" do
      bad = batched_bill("SBI-SETTLE-RAISE-BAD-2", 942)
      allow(SwayLogging).to receive(:log_exception)
      allow(SummaryRunSettle).to receive(:completed!).and_wrap_original do |original, bill, provisioning, **kwargs|
        raise Llm::TransportError, "settle refused" if bill.id == bad.id

        original.call(bill, provisioning, **kwargs)
      end

      ingest!([ok_summary(bad), ok_positions(bad)], ended_status(succeeded: 2))

      expect(SwayLogging).to have_received(:log_exception).with(
        "summary_batch_ingest.bill_not_settled", hash_including(bill_id: bad.id)
      )
    end
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#One stage-result writer for the job and the ingest]]
  describe "a bill the run holds no row for" do
    it "says the stage result could not be recorded against it" do
      bill = batched_bill("SBI-NO-BILL-RUN", 950)
      run.pipeline_run_bills.where(bill_external_id: bill.external_id).delete_all
      allow(SwayLogging).to receive(:warn)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(SwayLogging).to have_received(:warn).with(
        "summary_batch_ingest.no_bill_run", hash_including(bill_id: bill.id)
      )
    end

    it "settles the bill rather than leaving it for the reclaim sweep" do
      bill = batched_bill("SBI-NO-BILL-RUN-2", 951)
      run.pipeline_run_bills.where(bill_external_id: bill.external_id).delete_all
      allow(SwayLogging).to receive(:warn)
      allow(SwayLogging).to receive(:log_exception)

      ingest!([ok_summary(bill), ok_positions(bill)])

      expect(SwayLogging).not_to have_received(:log_exception)
    end
  end

  describe "batch retry model isolation with OpenRouter summaries" do
    it "retains the batch's original Claude model for retries when AdminSetting changed to OpenRouter" do
      batch.update!(model: "claude-sonnet-5-5")
      AdminSetting.singleton.update_columns(summarization_model: "Deepseek Pro Latest")
      bill = batched_bill("SBI-RETRY-OR-ISOLATION", 860)

      submitted_items = nil
      allow(Llm::ClaudeBatchService).to receive(:submit) do |items:|
        submitted_items = items
        double(id: "msgbatch_retry", expires_at: retry_expires_at)
      end

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(submitted_items).not_to be_nil
      expect(submitted_items.first.model).to eq("claude-sonnet-5-5")
      expect(submitted_items.first.model).not_to include("deepseek")
      expect(run.pipeline_run_summary_batches.find_by(batch_id: "msgbatch_retry").model).to eq("claude-sonnet-5-5")
    end

    it "falls back to an active Claude model rather than an OpenRouter model if batch.model is missing" do
      batch.update!(model: nil)
      AdminSetting.singleton.update_columns(summarization_model: "Deepseek Pro Latest")
      bill = batched_bill("SBI-RETRY-OR-FALLBACK", 861)

      submitted_items = nil
      allow(Llm::ClaudeBatchService).to receive(:submit) do |items:|
        submitted_items = items
        double(id: "msgbatch_retry", expires_at: retry_expires_at)
      end

      ingest!([failed_item(bill, SummaryBatchItem::SUMMARY)], ended_status(errored: 1))

      expect(submitted_items).not_to be_nil
      expect(submitted_items.first.model).to eq("claude-haiku-5-5")
      expect(submitted_items.first.model).not_to include("deepseek")
      expect(run.pipeline_run_summary_batches.find_by(batch_id: "msgbatch_retry").model).to eq("claude-haiku-5-5")
    end
  end

  describe "batch summarisation token usage counting" do
    before do
      allow(SwayLogging).to receive(:info).and_call_original
    end

    it "records usage on successful batch item ingestion" do
      bill = batched_bill("SBI-USAGE-OK", 870)
      usage = double(
        "Usage",
        input_tokens: 1800,
        output_tokens: 420,
        cache_creation_input_tokens: 250,
        cache_read_input_tokens: 150
      )
      result = Llm::ClaudeBatchService::Result.new(
        custom_id: cid(bill, SummaryBatchItem::SUMMARY),
        value: {"summary_markdown" => "A short summary.", "full_breakdown_markdown" => "## Section 1"},
        error: nil,
        usage: usage,
        model: "claude-sonnet-5-5"
      )

      expect(SwayLogging).to receive(:info).with(
        "claude.usage.recorded.batch",
        model: "claude-sonnet-5-5",
        input_tokens: 1800,
        output_tokens: 420,
        cache_creation_input_tokens: 250,
        cache_read_input_tokens: 150
      )

      ingest!([result, ok_positions(bill)], ended_status(succeeded: 2))
    end

    it "emits no usage record for a failed batch item with nil usage" do
      bill = batched_bill("SBI-USAGE-FAIL", 871)
      result = failed_item(bill, SummaryBatchItem::SUMMARY)

      expect(SwayLogging).not_to receive(:info).with("claude.usage.recorded.batch", any_args)
      expect(SwayLogging).not_to receive(:info).with("claude.usage.recorded", any_args)

      ingest!([result], ended_status(errored: 1))
    end

    it "formats integers so shell pipeline can sum direct and batch tokens together" do
      bill = batched_bill("SBI-USAGE-INTEGERS", 872)
      usage = double("Usage", input_tokens: 2500, output_tokens: 600)
      result = Llm::ClaudeBatchService::Result.new(
        custom_id: cid(bill, SummaryBatchItem::SUMMARY),
        value: {"summary_markdown" => "A short summary.", "full_breakdown_markdown" => "## Section 1"},
        error: nil,
        usage: usage,
        model: "claude-sonnet-5-5"
      )

      log_output = nil
      allow(Rails.logger).to receive(:info) do |msg|
        log_output = msg if msg.to_s.include?("claude.usage.recorded.batch")
      end

      ingest!([result, ok_positions(bill)], ended_status(succeeded: 2))

      expect(log_output).to include("claude.usage.recorded.batch")
      expect(log_output).to include("input_tokens=2500")
      expect(log_output).to include("output_tokens=600")
      expect(log_output).not_to include("[FILTERED]")
    end
  end
end
