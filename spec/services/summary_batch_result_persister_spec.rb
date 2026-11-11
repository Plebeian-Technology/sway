# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Batch summarisation#What identity a batch result writes as its receipt]]
RSpec.describe SummaryBatchResultPersister do
  let(:sway_locale) { SwayLocale.find_by(city: "baltimore") || create(:sway_locale, :baltimore) }
  let(:batch_id) { "msgbatch_persist" }
  let(:bill) do
    create(:bill, external_id: "SBRP-1", sway_locale: sway_locale,
      extracted_text: "Section 1.", scheduled_release_date_utc: 720.days.ago)
  end
  let(:provisioning) { create(:bill_llm_provisioning, :generating, :with_testimony, bill: bill) }

  def batch_summary_result(overrides = {})
    Llm::ClaudeBatchService::Result.new(
      custom_id: SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::SUMMARY),
      value: {
        "summary_markdown" => "A short summary.",
        "full_breakdown_markdown" => "## Section 1",
        "news_usage" => "none"
      }.merge(overrides),
      error: nil,
      usage: nil,
      model: "claude-sonnet-5-20260101"
    )
  end

  def positions_result(positions = [{"org_name" => "Test Org", "stance" => "support", "summary" => "Yes"}])
    Llm::ClaudeBatchService::Result.new(
      custom_id: SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::POSITIONS),
      value: {"draft_org_positions" => positions},
      error: nil,
      usage: nil,
      model: "claude-sonnet-5-20260101"
    )
  end

  def persist_summary(result: batch_summary_result, active_categories: [])
    described_class.call(
      bill: bill, provisioning: provisioning, answer_type: SummaryBatchItem::SUMMARY,
      result: result, batch_id: batch_id, active_categories: active_categories
    )
  end

  def persist_positions(result: positions_result)
    described_class.call(
      bill: bill, provisioning: provisioning, answer_type: SummaryBatchItem::POSITIONS,
      result: result, batch_id: batch_id, active_categories: []
    )
  end

  describe "the summary answer" do
    it "reports the guard's verdict" do
      expect(persist_summary).to eq(:persisted)
    end

    it "writes the summary body" do
      persist_summary

      expect(provisioning.reload.llm_summary).to eq("A short summary.")
    end

    it "writes the full breakdown" do
      persist_summary

      expect(provisioning.reload.llm_full_breakdown).to eq("## Section 1")
    end

    it "records claude as the provider, which the batch API gives no adapter to ask" do
      persist_summary

      expect(provisioning.reload.llm_provider).to eq("claude")
    end

    it "records the model that actually answered, not the one the request asked for" do
      persist_summary

      expect(provisioning.reload.llm_model).to eq("claude-sonnet-5-20260101")
    end

    it "stamps llm_generated_at" do
      persist_summary

      expect(provisioning.reload.llm_generated_at).to be_present
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#What identity a batch result writes as its receipt]]
    it "writes the bare batch marker as its receipt, not the run claim" do
      persist_summary

      expect(provisioning.reload.summary_run_id)
        .to eq(SummaryRunMarker.batch_run_id(batch_id: batch_id, bill_id: bill.id))
    end

    it "runs the citation verdict over the payload" do
      persist_summary(result: batch_summary_result("cited_section_keys" => ["nowhere"]))

      expect(provisioning.reload.citations_valid).to be(false)
    end

    it "runs the news URL citation verdict over the payload" do
      provisioning.update!(
        news_articles: [{"url" => "https://example.com/valid", "title" => "Valid"}]
      )
      persist_summary(result: batch_summary_result("cited_news_urls" => ["https://example.com/unlisted"]))

      provisioning.reload
      expect(provisioning.news_urls_valid).to be(false)
      expect(provisioning.invalid_news_urls).to eq(["https://example.com/unlisted"])
    end

    it "publishes the summary onto a bill nobody has written one for" do
      bill.update_columns(summary: "")

      persist_summary

      expect(bill.reload.summary).to eq("A short summary.")
    end

    it "leaves a hand-written published summary alone" do
      bill.update_columns(summary: "A person wrote this one.")

      persist_summary

      expect(bill.reload.summary).to eq("A person wrote this one.")
    end

    describe "news-bearing batch result ingestion" do
      let(:news_article) { create(:news_article, canonical_url: "https://example.com/banner-batch", outlet_name: "The Baltimore Banner", title: "Batch News Story") }
      let(:text_version) { create(:news_article_text_version, :extracted, news_article: news_article, text: "The council voted 12-2 to approve the affordable housing mandate.") }
      let!(:bna) { create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version, match_kind: "direct") }
      let!(:snapshot) do
        custom_id = SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::SUMMARY)
        NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "summary",
          run_receipt: custom_id,
          sources: [bna]
        )
      end

      it "ingests news-bearing batch result, attaches pending source uses to snapshot, and isolates revision as draft" do
        grounding_adapter = instance_double(Llm::ClaudeAdapter)
        allow(Llm::Client).to receive(:build).and_return(grounding_adapter)
        allow(grounding_adapter).to receive(:generate_news_claim_grounding)
          .and_return({"verdict" => "supported", "reason" => "The article supports the council approval claim."})

        payload = {
          "summary_markdown" => "The council approved the housing mandate [The Baltimore Banner](https://example.com/banner-batch).",
          "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
          "news_usage" => "cited",
          "cited_news_urls" => ["https://example.com/banner-batch"],
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "The council approved the housing mandate",
              "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
              "citation_url" => "https://example.com/banner-batch"
            }
          ]
        }
        result = batch_summary_result(payload)

        expect(persist_summary(result: result)).to eq(:persisted)

        expect(snapshot.source_uses.count).to eq(1)
        use = snapshot.source_uses.first!
        expect(use.bill_news_article_id).to eq(bna.id)
        expect(use.text_version_id).to eq(text_version.id)
        expect(use.claim_text).to eq("The council approved the housing mandate")
        expect(use.evidence_excerpt).to eq("voted 12-2 to approve the affordable housing mandate")
        expect(use.citation_url).to eq("https://example.com/banner-batch")
        expect(use.grounding_status).to eq("supported")

        revision = bill.bill_summary_revisions.order(created_at: :desc).first!
        expect(revision.publication_role).to eq("draft")
        expect(revision.news_source_snapshot_id).to eq(snapshot.id)
        expect(revision.summary_markdown).to eq(payload["summary_markdown"])

        expect(bill.reload.summary).not_to eq(payload["summary_markdown"])
      end

      it "rejects the batch summary as a whole and persists zero source uses when one source use is valid and another has an invalid excerpt on the same URL" do
        bill.update_columns(summary: "Historical approved public summary.")
        provisioning.update_columns(llm_summary: "Historical approved public summary.")
        payload_with_mixed_claims = {
          "summary_markdown" => "The council approved the housing mandate and 999 parks [The Baltimore Banner](https://example.com/banner-batch).",
          "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
          "news_usage" => "cited",
          "cited_news_urls" => ["https://example.com/banner-batch"],
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "The council approved the housing mandate",
              "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
              "citation_url" => "https://example.com/banner-batch"
            },
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "999 parks closed",
              "evidence_excerpt" => "closed 999 parks across the district",
              "citation_url" => "https://example.com/banner-batch"
            }
          ]
        }
        result = batch_summary_result(payload_with_mixed_claims)

        persist_summary(result: result)

        expect(bill.reload.summary).to eq("Historical approved public summary.")
        expect(snapshot.source_uses.count).to eq(0)
        expect(provisioning.reload.generation_error).to include("Evidence excerpt does not appear verbatim in article text version")
        expect(provisioning.reload.llm_summary).to eq(payload_with_mixed_claims["summary_markdown"])
        revision = bill.bill_summary_revisions.order(created_at: :desc).first!
        expect(revision.publication_role).to eq("draft")
        expect(revision.summary_markdown).to eq(payload_with_mixed_claims["summary_markdown"])
      end

      it "rejects the batch summary when news_usage is 'none' but source_uses is non-empty" do
        bill.update_columns(summary: "Historical approved public summary.")
        provisioning.update_columns(llm_summary: "Historical approved public summary.")
        payload = {
          "summary_markdown" => "The council approved the housing mandate without news.",
          "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
          "news_usage" => "none",
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "The council approved the housing mandate",
              "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
              "citation_url" => "https://example.com/banner-batch"
            }
          ]
        }
        result = batch_summary_result(payload)

        persist_summary(result: result)

        expect(bill.reload.summary).to eq("Historical approved public summary.")
        expect(provisioning.reload.generation_error).to include("Declared no-news usage but source-use manifest is not empty")
        expect(bill.bill_summary_revisions.order(created_at: :desc).first.publication_role).to eq("draft")
      end

      it "rejects the batch summary when news_usage is missing without inferring 'none'" do
        bill.update_columns(summary: "Historical approved public summary.")
        provisioning.update_columns(llm_summary: "Historical approved public summary.")
        payload = {
          "summary_markdown" => "The council approved the housing mandate without news.",
          "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
          "news_usage" => nil,
          "source_uses" => []
        }
        result = batch_summary_result(payload)

        persist_summary(result: result)

        expect(bill.reload.summary).to eq("Historical approved public summary.")
        expect(provisioning.reload.generation_error).to include("Missing or invalid news_usage declaration")
        expect(bill.bill_summary_revisions.order(created_at: :desc).first.publication_role).to eq("draft")
      end

      it "rejects the batch summary when news_usage is invalid without inferring 'none'" do
        bill.update_columns(summary: "Historical approved public summary.")
        provisioning.update_columns(llm_summary: "Historical approved public summary.")
        payload = {
          "summary_markdown" => "The council approved the housing mandate without news.",
          "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
          "news_usage" => "unspecified",
          "source_uses" => []
        }
        result = batch_summary_result(payload)

        persist_summary(result: result)

        expect(bill.reload.summary).to eq("Historical approved public summary.")
        expect(provisioning.reload.generation_error).to include("Missing or invalid news_usage declaration")
        expect(bill.bill_summary_revisions.order(created_at: :desc).first.publication_role).to eq("draft")
      end

      it "raises Llm::SchemaError when SummaryRunPersistGuard returns :grounding_refused" do
        allow(SummaryRunPersistGuard).to receive(:call).and_return(:grounding_refused)
        provisioning.update_columns(generation_error: "Grounding validation refused")

        expect {
          persist_summary(result: batch_summary_result)
        }.to raise_error(Llm::SchemaError, /Grounding validation refused/)
      end
    end
  end

  describe "categories on a batch-summarised bill" do
    it "assigns the categories the answer named" do
      category = create(:category, name: "Housing", active: true)

      persist_summary(result: batch_summary_result("categories" => ["Housing"]), active_categories: [category])

      expect(bill.reload.categories.pluck(:name)).to eq(["Housing"])
    end

    it "completes uncategorized rather than raising when no name matches the active set" do
      category = create(:category, name: "Housing", active: true)
      allow(SwayLogging).to receive(:warn)

      expect {
        persist_summary(result: batch_summary_result("categories" => ["Nothing Like It"]), active_categories: [category])
      }.not_to raise_error
    end

    it "says so when the answer named no category" do
      allow(SwayLogging).to receive(:warn)

      persist_summary(result: batch_summary_result, active_categories: [create(:category, active: true)])

      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary.no_categories_in_response", hash_including(bill_id: bill.id)
      )
    end

    it "says so when there is no active category to assign from" do
      allow(SwayLogging).to receive(:warn)

      persist_summary(result: batch_summary_result("categories" => ["Housing"]), active_categories: [])

      expect(SwayLogging).to have_received(:warn).with(
        "generate_bill_summary.no_active_categories", hash_including(bill_id: bill.id)
      )
    end

    it "assigns nothing when the guard declined the write" do
      category = create(:category, name: "Housing", active: true)
      provisioning.update_columns(summary_run_id: SummaryRunMarker.operator_paste)

      persist_summary(result: batch_summary_result("categories" => ["Housing"]), active_categories: [category])

      expect(bill.reload.categories).to be_empty
    end

    describe "validated news publication gating" do
      let(:news_article) { create(:news_article, canonical_url: "https://example.com/banner-batch-gate", outlet_name: "The Baltimore Banner", title: "Batch Gate Story") }
      let(:text_version) { create(:news_article_text_version, :extracted, news_article: news_article, text: "The council voted 12-2 to approve the affordable housing mandate.") }
      let!(:bna) { create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version, match_kind: "direct") }
      let!(:snapshot) do
        custom_id = SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::SUMMARY)
        NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "summary",
          run_receipt: custom_id,
          sources: [bna]
        )
      end

      it "publishes the summary when cited news claims are supported and version locks are fresh" do
        bill.update_columns(summary: "")
        payload = {
          "summary_markdown" => "The council approved the housing mandate [The Baltimore Banner](https://example.com/banner-batch-gate).",
          "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
          "news_usage" => "cited",
          "cited_news_urls" => ["https://example.com/banner-batch-gate"],
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "The council approved the housing mandate",
              "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
              "citation_url" => "https://example.com/banner-batch-gate"
            }
          ]
        }
        result = batch_summary_result(payload)

        supported_result = instance_double(
          NewsClaimGroundingService::Result,
          supported?: true,
          unsupported?: false,
          indeterminate?: false,
          verdict: "supported",
          errors: []
        )
        allow(NewsClaimGroundingService).to receive(:call).and_return(supported_result)

        expect(persist_summary(result: result)).to eq(:persisted)

        revision = bill.bill_summary_revisions.order(created_at: :desc).first!
        expect(revision.publication_role).to eq("published")
        expect(revision.news_source_snapshot_id).to eq(snapshot.id)
        expect(bill.reload.summary).to eq(payload["summary_markdown"])
      end

      it "refuses publication and quarantines draft when cited news claims are unsupported" do
        bill.update_columns(summary: "")
        payload = {
          "summary_markdown" => "The council approved the housing mandate [The Baltimore Banner](https://example.com/banner-batch-gate).",
          "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
          "news_usage" => "cited",
          "cited_news_urls" => ["https://example.com/banner-batch-gate"],
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "The council approved the housing mandate",
              "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
              "citation_url" => "https://example.com/banner-batch-gate"
            }
          ]
        }
        result = batch_summary_result(payload)

        unsupported_result = instance_double(
          NewsClaimGroundingService::Result,
          supported?: false,
          unsupported?: true,
          indeterminate?: false,
          verdict: "unsupported",
          errors: ["Claim is unsupported by article text"]
        )
        allow(NewsClaimGroundingService).to receive(:call).and_return(unsupported_result)

        expect(persist_summary(result: result)).to eq(:persisted)

        revision = bill.bill_summary_revisions.order(created_at: :desc).first!
        expect(revision.publication_role).to eq("draft")
        expect(bill.reload.summary).to be_blank
        expect(provisioning.reload.generation_error).to include("Claim is unsupported by article text")
      end

      it "refuses publication when article approval was withdrawn while batch was in-flight" do
        bill.update_columns(summary: "")
        payload = {
          "summary_markdown" => "The council approved the housing mandate [The Baltimore Banner](https://example.com/banner-batch-gate).",
          "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
          "news_usage" => "cited",
          "cited_news_urls" => ["https://example.com/banner-batch-gate"],
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "The council approved the housing mandate",
              "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
              "citation_url" => "https://example.com/banner-batch-gate"
            }
          ]
        }
        result = batch_summary_result(payload)

        supported_result = instance_double(
          NewsClaimGroundingService::Result,
          supported?: true,
          unsupported?: false,
          indeterminate?: false,
          verdict: "supported",
          errors: []
        )
        allow(NewsClaimGroundingService).to receive(:call).and_return(supported_result)

        # Withdraw approval while batch was in flight
        bna.withdraw_approval!(by: create(:user, :sway_admin))

        expect(persist_summary(result: result)).to eq(:persisted)

        revision = bill.bill_summary_revisions.order(created_at: :desc).first!
        expect(revision.publication_role).to eq("draft")
        expect(bill.reload.summary).to be_blank
        expect(provisioning.reload.generation_error).to match(/approval has been withdrawn/i)
      end
    end

    describe "submission attempt isolation and stale response rejection" do
      let(:news_article) { create(:news_article, canonical_url: "https://example.com/banner-batch-gate", outlet_name: "The Baltimore Banner", title: "Batch Gate Story") }
      let(:text_version) { create(:news_article_text_version, :extracted, news_article: news_article, text: "The council voted 12-2 to approve the affordable housing mandate.") }
      let!(:bna) { create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version, match_kind: "direct") }

      it "isolates source uses across successive submissions without mutating prior run evidence" do
        bill.update_columns(summary: "")
        run_a = create(:legislation_pipeline_run, bill: nil)
        batch_a = create(:pipeline_run_summary_batch, legislation_pipeline_run: run_a, batch_id: "msgbatch_run_a_iso")
        receipt_a = SummaryRunMarker.batch_pending_id(run_id: run_a.id, bill_id: bill.id)

        snapshot_a = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "summary",
          run_receipt: receipt_a,
          sources: [bna]
        )

        provisioning.update!(
          summary_batch_id: batch_a.batch_id,
          summary_run_id: SummaryRunMarker.run_claim(SummaryRunMarker.batch_run_id(batch_id: batch_a.batch_id, bill_id: bill.id))
        )

        payload_a = {
          "summary_markdown" => "Council approved housing mandate [The Baltimore Banner](https://example.com/banner-batch-gate).",
          "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
          "news_usage" => "cited",
          "cited_news_urls" => ["https://example.com/banner-batch-gate"],
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "Council approved housing mandate",
              "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
              "citation_url" => "https://example.com/banner-batch-gate"
            }
          ]
        }
        result_a = batch_summary_result(payload_a)

        supported_result = instance_double(
          NewsClaimGroundingService::Result,
          supported?: true, unsupported?: false, indeterminate?: false,
          verdict: "supported", errors: []
        )
        allow(NewsClaimGroundingService).to receive(:call).and_return(supported_result)

        expect(described_class.call(
          bill: bill, provisioning: provisioning, answer_type: SummaryBatchItem::SUMMARY,
          result: result_a, batch_id: batch_a.batch_id
        )).to eq(:persisted)

        expect(bill.reload.summary).to eq(payload_a["summary_markdown"])
        expect(snapshot_a.source_uses.count).to eq(1)
        original_use_id = snapshot_a.source_uses.first.id

        run_b = create(:legislation_pipeline_run, bill: nil)
        batch_b = create(:pipeline_run_summary_batch, legislation_pipeline_run: run_b, batch_id: "msgbatch_run_b_iso")
        receipt_b = SummaryRunMarker.batch_pending_id(run_id: run_b.id, bill_id: bill.id)

        snapshot_b = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "summary",
          run_receipt: receipt_b,
          sources: [bna]
        )
        expect(snapshot_b.id).not_to eq(snapshot_a.id)

        provisioning.update!(
          summary_batch_id: batch_b.batch_id,
          summary_run_id: SummaryRunMarker.run_claim(SummaryRunMarker.batch_run_id(batch_id: batch_b.batch_id, bill_id: bill.id))
        )

        payload_b = {
          "summary_markdown" => "Affordable housing mandate passed 12-2 [The Baltimore Banner](https://example.com/banner-batch-gate).",
          "full_breakdown_markdown" => "## Section 1\nHousing mandate details updated.",
          "news_usage" => "cited",
          "cited_news_urls" => ["https://example.com/banner-batch-gate"],
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "Affordable housing mandate passed 12-2",
              "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
              "citation_url" => "https://example.com/banner-batch-gate"
            }
          ]
        }
        result_b = batch_summary_result(payload_b)

        expect(described_class.call(
          bill: bill, provisioning: provisioning.reload, answer_type: SummaryBatchItem::SUMMARY,
          result: result_b, batch_id: batch_b.batch_id
        )).to eq(:persisted)

        revision_b = bill.bill_summary_revisions.order(created_at: :desc).first!
        expect(revision_b.news_source_snapshot_id).to eq(snapshot_b.id)
        expect(snapshot_b.source_uses.count).to eq(1)
        expect(snapshot_b.source_uses.first.claim_text).to eq("Affordable housing mandate passed 12-2")

        expect(snapshot_a.reload.source_uses.count).to eq(1)
        expect(snapshot_a.source_uses.first.id).to eq(original_use_id)
        expect(snapshot_a.source_uses.first.claim_text).to eq("Council approved housing mandate")
      end

      it "resolves Run A's exact evidence snapshot when returning late after Run B captured replacement text and rejects Run A as stale" do
        bill.update_columns(summary: "")
        run_a = create(:legislation_pipeline_run, bill: nil)
        batch_a = create(:pipeline_run_summary_batch, legislation_pipeline_run: run_a, batch_id: "msgbatch_run_a_stale")
        receipt_a = SummaryRunMarker.batch_pending_id(run_id: run_a.id, bill_id: bill.id)

        snapshot_a = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "summary",
          run_receipt: receipt_a,
          sources: [bna]
        )

        text_version_2 = create(
          :news_article_text_version,
          :extracted,
          news_article: news_article,
          text: "Amended housing text: council passed revised version with tax amendments."
        )
        bna.update!(current_text_version: text_version_2)

        run_b = create(:legislation_pipeline_run, bill: nil)
        batch_b = create(:pipeline_run_summary_batch, legislation_pipeline_run: run_b, batch_id: "msgbatch_run_b_active")
        receipt_b = SummaryRunMarker.batch_pending_id(run_id: run_b.id, bill_id: bill.id)

        snapshot_b = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "summary",
          run_receipt: receipt_b,
          sources: [bna]
        )

        provisioning.update!(
          summary_batch_id: batch_b.batch_id,
          summary_run_id: SummaryRunMarker.run_claim(SummaryRunMarker.batch_run_id(batch_id: batch_b.batch_id, bill_id: bill.id))
        )
        payload_b = {
          "summary_markdown" => "Run B published summary: Revised version passed with tax amendments [The Baltimore Banner](https://example.com/banner-batch-gate).",
          "full_breakdown_markdown" => "## Section 1\nRun B details.",
          "news_usage" => "cited",
          "cited_news_urls" => ["https://example.com/banner-batch-gate"],
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version_2.id,
              "claim_text" => "Revised version passed with tax amendments",
              "evidence_excerpt" => "council passed revised version with tax amendments",
              "citation_url" => "https://example.com/banner-batch-gate"
            }
          ]
        }
        result_b = batch_summary_result(payload_b)
        supported_result = instance_double(
          NewsClaimGroundingService::Result,
          supported?: true, unsupported?: false, indeterminate?: false,
          verdict: "supported", errors: []
        )
        allow(NewsClaimGroundingService).to receive(:call).and_return(supported_result)

        described_class.call(
          bill: bill, provisioning: provisioning.reload, answer_type: SummaryBatchItem::SUMMARY,
          result: result_b, batch_id: batch_b.batch_id
        )
        expect(bill.reload.summary).to eq(payload_b["summary_markdown"])

        payload_a = {
          "summary_markdown" => "Run A late returning summary: Council approved housing mandate [The Baltimore Banner](https://example.com/banner-batch-gate).",
          "full_breakdown_markdown" => "## Section 1\nRun A details.",
          "news_usage" => "cited",
          "cited_news_urls" => ["https://example.com/banner-batch-gate"],
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "Council approved housing mandate",
              "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
              "citation_url" => "https://example.com/banner-batch-gate"
            }
          ]
        }
        result_a = batch_summary_result(payload_a)

        outcome = described_class.call(
          bill: bill, provisioning: provisioning.reload, answer_type: SummaryBatchItem::SUMMARY,
          result: result_a, batch_id: batch_a.batch_id
        )

        expect(outcome).to eq(:persisted)
        revision_a = bill.bill_summary_revisions.order(created_at: :desc).first!
        expect(revision_a.news_source_snapshot_id).to eq(snapshot_a.id)
        expect(revision_a.news_source_snapshot_id).not_to eq(snapshot_b.id)
        expect(revision_a.publication_role).to eq("draft")
        expect(bill.reload.summary).to eq(payload_b["summary_markdown"])
        expect(provisioning.reload.generation_error).to match(/text version changed/i)
      end

      it "quarantines draft and preserves published summary when article stance changes after snapshot capture" do
        admin = create(:user, :sway_admin)
        bna.set_stance!("support", by: admin)
        bill.update_columns(summary: "Published summary before stance shift.")
        create(
          :bill_summary_revision,
          bill: bill,
          summary_markdown: "Published summary before stance shift.",
          origin: "model_generation",
          publication_role: "published",
          review_state: "unreviewed"
        )
        provisioning.update!(llm_summary: "Published summary before stance shift.")

        run_stance = create(:legislation_pipeline_run, bill: nil)
        batch_stance = create(:pipeline_run_summary_batch, legislation_pipeline_run: run_stance, batch_id: "msgbatch_stance_mod")
        receipt_stance = SummaryRunMarker.batch_pending_id(run_id: run_stance.id, bill_id: bill.id)

        snapshot_stance = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "summary",
          run_receipt: receipt_stance,
          sources: [bna]
        )

        provisioning.update!(
          summary_batch_id: batch_stance.batch_id,
          summary_run_id: SummaryRunMarker.run_claim(SummaryRunMarker.batch_run_id(batch_id: batch_stance.batch_id, bill_id: bill.id))
        )

        bna.set_stance!("oppose", by: admin)

        payload_stance = {
          "summary_markdown" => "Council approved housing mandate [The Baltimore Banner](https://example.com/banner-batch-gate).",
          "full_breakdown_markdown" => "## Section 1\nStance details.",
          "news_usage" => "cited",
          "cited_news_urls" => ["https://example.com/banner-batch-gate"],
          "source_uses" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => "Council approved housing mandate",
              "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
              "citation_url" => "https://example.com/banner-batch-gate"
            }
          ]
        }
        result_stance = batch_summary_result(payload_stance)
        supported_result = instance_double(
          NewsClaimGroundingService::Result,
          supported?: true, unsupported?: false, indeterminate?: false,
          verdict: "supported", errors: []
        )
        allow(NewsClaimGroundingService).to receive(:call).and_return(supported_result)

        outcome = described_class.call(
          bill: bill, provisioning: provisioning.reload, answer_type: SummaryBatchItem::SUMMARY,
          result: result_stance, batch_id: batch_stance.batch_id
        )

        expect(outcome).to eq(:persisted)
        expect(bill.reload.summary).to eq("Published summary before stance shift.")
        revision = bill.bill_summary_revisions.order(created_at: :desc, id: :desc).first!
        expect(revision.publication_role).to eq("draft")
        expect(revision.news_source_snapshot_id).to eq(snapshot_stance.id)
        expect(provisioning.reload.generation_error).to match(/stance changed from support to oppose/i)
      end

      it "isolates dual-purpose summary and testimony snapshots across out-of-order batch runs" do
        bill.update_columns(summary: "")
        op_ed = create(:news_article, :editorial, outlet_name: "The Baltimore Sun", title: "Sun Editorial", canonical_url: "https://example.com/sun-dual-ed")
        op_ed_tv1 = create(:news_article_text_version, :extracted, news_article: op_ed, text: "The Sun editorial board urges council to vote yes on the housing mandate.")
        bna_op = create(:bill_news_article, :approved, bill: bill, news_article: op_ed, current_text_version: op_ed_tv1, stance: "support", match_kind: "direct")

        run_a = create(:legislation_pipeline_run, bill: nil)
        batch_a = create(:pipeline_run_summary_batch, legislation_pipeline_run: run_a, batch_id: "msgbatch_dual_a")
        receipt_a = SummaryRunMarker.batch_pending_id(run_id: run_a.id, bill_id: bill.id)

        sum_snap_a = NewsArticleSourceSnapshotService.capture!(bill: bill, purpose: "summary", run_receipt: receipt_a, sources: [bna, bna_op])
        test_snap_a = NewsArticleSourceSnapshotService.capture!(bill: bill, purpose: "testimony", run_receipt: receipt_a, sources: [bna_op])

        op_ed_tv2 = create(:news_article_text_version, :extracted, news_article: op_ed, text: "Updated editorial: The Sun editorial board strongly backs the amended housing mandate.")
        bna_op.update!(current_text_version: op_ed_tv2)

        run_b = create(:legislation_pipeline_run, bill: nil)
        batch_b = create(:pipeline_run_summary_batch, legislation_pipeline_run: run_b, batch_id: "msgbatch_dual_b")
        receipt_b = SummaryRunMarker.batch_pending_id(run_id: run_b.id, bill_id: bill.id)

        sum_snap_b = NewsArticleSourceSnapshotService.capture!(bill: bill, purpose: "summary", run_receipt: receipt_b, sources: [bna, bna_op])
        test_snap_b = NewsArticleSourceSnapshotService.capture!(bill: bill, purpose: "testimony", run_receipt: receipt_b, sources: [bna_op])

        provisioning.update!(
          summary_batch_id: batch_b.batch_id,
          summary_batch_testimony_digest: provisioning.testimony_digest,
          summary_run_id: SummaryRunMarker.run_claim(SummaryRunMarker.batch_run_id(batch_id: batch_b.batch_id, bill_id: bill.id))
        )

        supported_result = instance_double(
          NewsClaimGroundingService::Result,
          supported?: true, unsupported?: false, indeterminate?: false,
          verdict: "supported", errors: []
        )
        allow(NewsClaimGroundingService).to receive(:call).and_return(supported_result)

        pos_result_b = Llm::ClaudeBatchService::Result.new(
          custom_id: SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::POSITIONS),
          value: {
            "draft_org_positions" => [],
            "draft_news_testimonies" => [
              {
                "bill_news_article_id" => bna_op.id,
                "text_version_id" => op_ed_tv2.id,
                "stance" => "support",
                "argument" => "Run B: Sun strongly backs amended housing mandate.",
                "evidence_excerpt" => "strongly backs the amended housing mandate",
                "outlet_name" => "The Baltimore Sun",
                "canonical_url" => "https://example.com/sun-dual-ed"
              }
            ]
          },
          error: nil, usage: nil, model: "claude-sonnet-5-20260101"
        )
        expect(described_class.call(
          bill: bill, provisioning: provisioning.reload, answer_type: SummaryBatchItem::POSITIONS,
          result: pos_result_b, batch_id: batch_b.batch_id
        )).to eq(:persisted)

        pos_result_a = Llm::ClaudeBatchService::Result.new(
          custom_id: SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::POSITIONS),
          value: {
            "draft_org_positions" => [],
            "draft_news_testimonies" => [
              {
                "bill_news_article_id" => bna_op.id,
                "text_version_id" => op_ed_tv1.id,
                "stance" => "support",
                "argument" => "Run A: Sun urges council to vote yes.",
                "evidence_excerpt" => "urges council to vote yes on the housing mandate",
                "outlet_name" => "The Baltimore Sun",
                "canonical_url" => "https://example.com/sun-dual-ed"
              }
            ]
          },
          error: nil, usage: nil, model: "claude-sonnet-5-20260101"
        )
        expect(described_class.call(
          bill: bill, provisioning: provisioning.reload, answer_type: SummaryBatchItem::POSITIONS,
          result: pos_result_a, batch_id: batch_a.batch_id
        )).to eq(:persisted)

        expect(sum_snap_a.reload.source_uses.count).to eq(0)
        expect(sum_snap_b.reload.source_uses.count).to eq(0)
        expect(test_snap_a.reload.source_uses.count).to eq(0)
        expect(test_snap_b.reload.source_uses.count).to eq(1)
        expect(bill.reload.news_testimonies.map(&:news_article_source_snapshot_id)).to eq([test_snap_b.id])
      end
    end
  end

  describe "the positions answer" do
    it "reports the guard's verdict" do
      provisioning.update_columns(summary_batch_testimony_digest: provisioning.testimony_digest)

      expect(persist_positions).to eq(:persisted)
    end

    it "writes the drafts" do
      provisioning.update_columns(summary_batch_testimony_digest: provisioning.testimony_digest)

      persist_positions

      expect(provisioning.reload.draft_org_positions.first["org_name"]).to eq("Test Org")
    end

    it "clears a stale generation_error" do
      provisioning.update_columns(
        summary_batch_testimony_digest: provisioning.testimony_digest, generation_error: "stale"
      )

      persist_positions

      expect(provisioning.reload.generation_error).to be_nil
    end

    # @lat: [[explanation/llm-summaries#Batch summarisation#Why the evidence digest is stamped at submit time]]
    it "checks the drafts against the digest stamped at submit time, not one taken now" do
      provisioning.update_columns(summary_batch_testimony_digest: "a digest from a different testimony")

      expect(persist_positions).to eq(:evidence_withdrawn)
    end

    it "leaves the existing drafts alone when the evidence was withdrawn" do
      provisioning.update_columns(
        summary_batch_testimony_digest: "a digest from a different testimony",
        draft_org_positions: [{"org_name" => "Old Org", "stance" => "oppose", "summary" => "No"}]
      )

      persist_positions

      expect(provisioning.reload.draft_org_positions.first["org_name"]).to eq("Old Org")
    end

    it "says on the row why the drafts were not saved" do
      provisioning.update_columns(summary_batch_testimony_digest: "a digest from a different testimony")

      persist_positions

      expect(provisioning.reload.generation_error)
        .to include(GenerateBillSummaryJob::POSITIONS_DISCARDED_PREFIX)
    end

    it "persists draft news testimonies and links pending source uses when testimony snapshot exists" do
      provisioning.update_columns(summary_batch_testimony_digest: provisioning.testimony_digest)
      news_article = create(:news_article, :editorial, outlet_name: "The Sun", title: "Editorial Support", canonical_url: "https://example.com/editorial")
      text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: "The city council must vote in favor of this bill.")
      bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version, stance: "support")

      item_custom_id = SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::POSITIONS)
      snapshot = NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "testimony",
        run_receipt: item_custom_id,
        sources: [bna]
      )

      result = Llm::ClaudeBatchService::Result.new(
        custom_id: item_custom_id,
        value: {
          "draft_org_positions" => [],
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "stance" => "support",
              "argument" => "The Sun editorial board strongly supports the housing bill.",
              "evidence_excerpt" => "vote in favor of this bill",
              "outlet_name" => "The Sun",
              "canonical_url" => "https://example.com/editorial"
            }
          ]
        },
        error: nil,
        usage: nil,
        model: "claude-sonnet-5-20260101"
      )

      allow(NewsArticleTestimonyService).to receive(:publish_commentary!)
      expect(persist_positions(result: result)).to eq(:persisted)

      testimony = bill.news_article_testimonies.first
      expect(testimony).to be_present
      expect(testimony.publication_state).to eq("draft")
      expect(testimony.argument_markdown).to eq("The Sun editorial board strongly supports the housing bill.")
      expect(testimony.evidence_excerpt).to eq("vote in favor of this bill")
      expect(testimony.news_article_source_snapshot_id).to eq(snapshot.id)

      expect(snapshot.source_uses.count).to eq(1)
      use = snapshot.source_uses.first
      expect(use.grounding_status).to eq("pending")
      expect(use.evidence_excerpt).to eq("vote in favor of this bill")
    end
  end

  context "opinion commentary publication gating" do
    let(:news_article) { create(:news_article, :editorial, outlet_name: "The Sun", title: "Editorial Support", canonical_url: "https://example.com/editorial") }
    let(:text_version) { create(:news_article_text_version, :extracted, news_article: news_article, text: "The city council must vote in favor of this bill.") }
    let!(:bna) { create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version, stance: "support") }

    let(:item_custom_id) { SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::POSITIONS) }
    let!(:snapshot) do
      NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "testimony",
        run_receipt: item_custom_id,
        sources: [bna]
      )
    end

    let(:positions_batch_result) do
      Llm::ClaudeBatchService::Result.new(
        custom_id: item_custom_id,
        value: {
          "draft_org_positions" => [],
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "stance" => "support",
              "argument" => "The Sun editorial board strongly supports the housing bill.",
              "evidence_excerpt" => "vote in favor of this bill",
              "outlet_name" => "The Sun",
              "canonical_url" => "https://example.com/editorial"
            }
          ]
        },
        error: nil,
        usage: nil,
        model: "claude-sonnet-5-20260101"
      )
    end

    it "publishes the draft commentary and makes it reachable in Bill#news_testimonies and BillResource" do
      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        verdict: "supported",
        errors: []
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(supported_grounding)

      expect(persist_positions(result: positions_batch_result)).to eq(:persisted)

      testimony = bill.news_article_testimonies.order(created_at: :desc).first!
      expect(testimony.publication_state).to eq("published")
      expect(testimony.published_at).to be_present

      expect(bill.reload.news_testimonies).to contain_exactly(testimony)

      raw_bill = BillResource.new(bill).serializable_hash #: Hash[Symbol, untyped]
      serialized_bill = raw_bill.with_indifferent_access
      expect(serialized_bill[:news_testimonies]).to be_present
      expect(serialized_bill[:news_testimonies].first[:id]).to eq(testimony.id)
      expect(serialized_bill[:news_testimonies].first[:outlet_name]).to eq("The Sun")
      expect(serialized_bill[:news_testimonies].first[:argument]).to eq("The Sun editorial board strongly supports the housing bill.")
    end

    it "leaves batch commentary in draft state when grounding is unsupported" do
      unsupported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: false,
        unsupported?: true,
        indeterminate?: false,
        verdict: "unsupported",
        errors: ["Grounding failed"]
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(unsupported_grounding)

      expect(persist_positions(result: positions_batch_result)).to eq(:persisted)

      testimony = bill.news_article_testimonies.order(created_at: :desc).first!
      expect(testimony.publication_state).to eq("draft")
      expect(testimony.published_at).to be_nil
      expect(bill.reload.news_testimonies).to be_empty
      raw_bill = BillResource.new(bill).serializable_hash #: Hash[Symbol, untyped]
      serialized_bill = raw_bill.with_indifferent_access
      expect(serialized_bill[:news_testimonies]).to be_blank
    end

    it "leaves batch commentary in draft state when grounding is indeterminate" do
      indeterminate_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: false,
        unsupported?: false,
        indeterminate?: true,
        verdict: "indeterminate",
        errors: ["Timed out"]
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(indeterminate_grounding)

      expect(persist_positions(result: positions_batch_result)).to eq(:persisted)

      testimony = bill.news_article_testimonies.order(created_at: :desc).first!
      expect(testimony.publication_state).to eq("draft")
      expect(bill.reload.news_testimonies).to be_empty
      raw_bill = BillResource.new(bill).serializable_hash #: Hash[Symbol, untyped]
      serialized_bill = raw_bill.with_indifferent_access
      expect(serialized_bill[:news_testimonies]).to be_blank
    end

    it "preserves prior valid published commentary when batch positions result fails grounding" do
      prior_testimony = create(
        :news_article_testimony,
        bill_news_article: bna,
        news_article_text_version: text_version,
        news_article_source_snapshot: NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "testimony",
          run_receipt: "receipt-batch-prior",
          sources: [bna]
        ),
        publication_state: "published",
        published_at: 1.day.ago,
        stance: "support",
        stance_version: bna.stance_version,
        review_version: bna.review_version,
        argument_markdown: "Prior published opinion.",
        evidence_excerpt: "vote in favor of this bill",
        citation_url: "https://example.com/editorial",
        outlet_name: "The Sun",
        text_digest: text_version.digest
      )

      unsupported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: false,
        unsupported?: true,
        indeterminate?: false,
        verdict: "unsupported",
        errors: ["Grounding failed"]
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(unsupported_grounding)

      persist_positions(result: positions_batch_result)

      expect(prior_testimony.reload.publication_state).to eq("published")
      expect(bill.reload.news_testimonies).to contain_exactly(prior_testimony)
      raw_bill = BillResource.new(bill).serializable_hash #: Hash[Symbol, untyped]
      serialized_bill = raw_bill.with_indifferent_access
      expect(serialized_bill[:news_testimonies].first[:id]).to eq(prior_testimony.id)
    end

    it "leaves batch commentary as draft when article stance changes in flight" do
      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        verdict: "supported",
        errors: []
      )
      allow(NewsClaimGroundingService).to receive(:call) do
        bna.update_columns(stance: "oppose", stance_version: 2)
        supported_grounding
      end

      expect(persist_positions(result: positions_batch_result)).to eq(:persisted)

      testimony = bill.news_article_testimonies.order(created_at: :desc).first
      expect(testimony).to be_present
      expect(testimony.publication_state).to eq("draft")
      expect(bill.reload.news_testimonies).to be_empty
    end

    it "leaves batch commentary as draft when article approval is withdrawn in flight" do
      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        verdict: "supported",
        errors: []
      )
      allow(NewsClaimGroundingService).to receive(:call) do
        bna.update_columns(approved: false)
        supported_grounding
      end

      expect(persist_positions(result: positions_batch_result)).to eq(:persisted)

      testimony = bill.news_article_testimonies.order(created_at: :desc).first
      expect(testimony).to be_present
      expect(testimony.publication_state).to eq("draft")
      expect(bill.reload.news_testimonies).to be_empty
    end

    it "leaves batch commentary as draft when article text version is replaced in flight" do
      new_tv = create(
        :news_article_text_version,
        :extracted,
        news_article: news_article,
        text: "Replacement article text."
      )
      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        verdict: "supported",
        errors: []
      )
      allow(NewsClaimGroundingService).to receive(:call) do
        bna.update_columns(current_text_version_id: new_tv.id)
        supported_grounding
      end

      expect(persist_positions(result: positions_batch_result)).to eq(:persisted)

      testimony = bill.news_article_testimonies.order(created_at: :desc).first
      expect(testimony).to be_present
      expect(testimony.publication_state).to eq("draft")
      expect(bill.reload.news_testimonies).to be_empty
    end

    it "stands down and does not persist or publish commentary when batch was superseded by an operator paste" do
      provisioning.update_columns(summary_run_id: SummaryRunMarker.operator_paste)

      expect(persist_positions(result: positions_batch_result)).to eq(:superseded)
      expect(bill.news_article_testimonies).to be_empty
    end

    it "persists and publishes batch news commentary without creating any Organization or OrganizationBillPosition records" do
      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        verdict: "supported",
        errors: []
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(supported_grounding)

      expect {
        persist_positions(result: positions_batch_result)
      }.to change(Organization, :count).by(0).and change(OrganizationBillPosition, :count).by(0)

      expect(bill.reload.active_organization_bill_positions).to be_empty
      expect(bill.news_testimonies.count).to eq(1)
    end
  end

  describe "an operator paste that landed while the batch was in flight" do
    before { provisioning.update_columns(summary_run_id: SummaryRunMarker.operator_paste) }

    it "reports the stand-down rather than overwriting the hand-written body" do
      expect(persist_summary).to eq(:superseded)
    end

    it "leaves the pasted body where it is" do
      provisioning.update_columns(llm_summary: "What a person wrote")

      persist_summary

      expect(provisioning.reload.llm_summary).to eq("What a person wrote")
    end

    it "writes the same activity-log entry the synchronous job writes" do
      persist_summary

      expect(PipelineActivityLogEntry.where(event_type: "summary_stood_down_for_paste")).to be_present
    end
  end

  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  describe "the record of what the last run read" do
    it "deletes it, because the batch's own prompt was built at submit time and kept nowhere" do
      create(:bill_summary_prompt_snapshot, bill: bill)

      expect(persist_summary).to eq(:persisted)
      expect(bill.reload.bill_summary_prompt_snapshot).to be_nil
    end
  end

  describe "a row deleted while the batch was in flight" do
    it "reports that the answer has nowhere to land" do
      provisioning
      BillLlmProvisioning.where(id: provisioning.id).delete_all
      allow(SwayLogging).to receive(:warn)

      expect(persist_summary).to eq(:vanished)
    end
  end

  describe "news reporting positions persistence and filtering" do
    let(:news_article) { create(:news_article, outlet_name: "The Baltimore Banner", title: "Housing Story", canonical_url: "https://example.com/housing") }
    let(:article_text) { "Jane Doe, executive director of the Baltimore Tenants Union, said: \"We need this protection now.\"" }
    let(:text_version) { create(:news_article_text_version, :extracted, news_article: news_article, text: article_text) }
    let!(:bna) { create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version) }

    let!(:summary_snapshot) do
      summary_custom_id = SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::SUMMARY)
      NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "summary",
        run_receipt: summary_custom_id,
        sources: [bna]
      )
    end

    let(:positions_result_with_news) do
      Llm::ClaudeBatchService::Result.new(
        custom_id: SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::POSITIONS),
        value: {
          "draft_org_positions" => [
            {
              "org_name" => "Baltimore Tenants Union",
              "stance" => "support",
              "summary" => "Initial summary",
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "evidence_excerpt" => "said: \"We need this protection now.\"",
              "speaker_name" => "Jane Doe",
              "speaker_role" => "executive director"
            }
          ]
        },
        error: nil,
        usage: nil,
        model: "claude-sonnet-5-20260101"
      )
    end

    it "resolves summary snapshot from positions result custom ID and persists grounded news drafts without hearing testimony" do
      provisioning.update!(extracted_testimony: nil, supplemental_testimony: nil, summary_batch_testimony_digest: nil)

      initial_org_count = Organization.count
      initial_pos_count = OrganizationBillPosition.count

      outcome = persist_positions(result: __send__(:positions_result_with_news))
      expect(outcome).to eq(:persisted)

      expect(Organization.count).to eq(initial_org_count)
      expect(OrganizationBillPosition.count).to eq(initial_pos_count)

      drafts = provisioning.reload.draft_org_positions
      expect(drafts).to be_present
      expect(drafts.length).to eq(1)
      first_draft = drafts.first
      expect(first_draft["org_name"]).to eq("Baltimore Tenants Union")
      expect(first_draft["source_url"]).to eq("https://example.com/housing")
      expect(first_draft["summary"]).to include("\"We need this protection now.\"")
    end

    it "drops ungrounded news drafts during batch positions persistence" do
      provisioning.update!(extracted_testimony: nil, supplemental_testimony: nil, summary_batch_testimony_digest: nil)
      ungrounded_result = Llm::ClaudeBatchService::Result.new(
        custom_id: SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::POSITIONS),
        value: {
          "draft_org_positions" => [
            {
              "org_name" => "Fake Org",
              "stance" => "oppose",
              "summary" => "Fake summary",
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "evidence_excerpt" => "nonexistent text",
              "speaker_name" => "Fake",
              "speaker_role" => "executive director"
            }
          ]
        },
        error: nil,
        usage: nil,
        model: "claude-sonnet-5-20260101"
      )

      outcome = persist_positions(result: ungrounded_result)
      expect(outcome).to eq(:persisted)
      expect(provisioning.reload.draft_org_positions).to eq([])
    end

    it "drops hearing-testimony positions when testimony is absent on the bill while persisting grounded news drafts" do
      provisioning.update!(extracted_testimony: nil, supplemental_testimony: nil, summary_batch_testimony_digest: nil)
      mixed_result = Llm::ClaudeBatchService::Result.new(
        custom_id: SummaryBatchItem.custom_id(bill_id: bill.id, answer_type: SummaryBatchItem::POSITIONS),
        value: {
          "draft_org_positions" => [
            {
              "org_name" => "Testimony Only Org",
              "stance" => "support",
              "summary" => "Claimed hearing testimony"
            },
            {
              "org_name" => "Baltimore Tenants Union",
              "stance" => "support",
              "summary" => "Initial summary",
              "bill_news_article_id" => bna.id,
              "text_version_id" => text_version.id,
              "evidence_excerpt" => "said: \"We need this protection now.\"",
              "speaker_name" => "Jane Doe",
              "speaker_role" => "executive director"
            }
          ]
        },
        error: nil,
        usage: nil,
        model: "claude-sonnet-5-20260101"
      )

      outcome = persist_positions(result: mixed_result)
      expect(outcome).to eq(:persisted)

      drafts = provisioning.reload.draft_org_positions
      expect(drafts.length).to eq(1)
      expect(drafts.first["org_name"]).to eq("Baltimore Tenants Union")
    end
  end
end
