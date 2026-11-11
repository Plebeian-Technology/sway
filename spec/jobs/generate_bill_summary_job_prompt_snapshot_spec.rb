# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
RSpec.describe GenerateBillSummaryJob do
  after { Sway::Settings.reset! }

  let(:bill) { create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.") }
  let!(:provisioning) { create(:bill_llm_provisioning, :pending, :with_diff_content, bill: bill) }
  let(:claude_adapter) { instance_double(Llm::ClaudeAdapter, provider_label: "claude") }

  let(:valid_payload) do
    {
      "summary_markdown" => "What changed: §1 amended to add reporting requirements.",
      "full_breakdown_markdown" => "## Section 1\nAdds quarterly reporting obligation."
    }
  end

  before do
    stub_app_config(:llm, llm_provider: "claude")
    allow(Llm::Client).to receive(:build).and_return(claude_adapter)
    allow(claude_adapter).to receive(:generate_bill_positions).and_return({"draft_org_positions" => []})
  end

  describe "a run whose summary lands" do
    it "records the four sections it sent, byte for byte" do
      sent = nil #: String?
      allow(claude_adapter).to receive(:generate_bill_summary) do |prompt:, **rest|
        sent = prompt.user_message
        valid_payload
      end

      described_class.perform_now(bill.id)

      snapshot = bill.reload.bill_summary_prompt_snapshot #: BillSummaryPromptSnapshot
      expect(snapshot).not_to be_nil
      rendered = [
        snapshot.bill_details_text, snapshot.source_text, snapshot.citations_text, snapshot.news_text
      ].compact.join("\n\n")
      expect(rendered).to eq(sent)
    end

    it "stamps the run that wrote it and the model that answered" do
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)

      job = described_class.new(bill.id)
      job.perform(bill.id)

      snapshot = bill.reload.bill_summary_prompt_snapshot #: BillSummaryPromptSnapshot
      expect(snapshot.summary_run_id).to eq(job.job_id)
      expect(snapshot.llm_provider).to eq("claude")
      expect(snapshot.llm_model).to be_present
      expect(snapshot.built_at).not_to be_nil
    end

    it "stores the counts the ledger renders, so a later re-extraction cannot move them" do
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)

      described_class.perform_now(bill.id)

      facts = bill.reload.bill_summary_prompt_snapshot.facts #: Hash[String, untyped]
      expect(facts["source_kind"]).to eq("extracted")
      expect(facts["source_chars"]).to eq("Section 1. The Mayor shall submit an annual report.".length)
      expect(facts).to have_key("diff_sections_not_found")
      expect(facts).to have_key("news_search_available")
    end

    it "replaces the bill's earlier record rather than adding a second one" do
      create(:bill_summary_prompt_snapshot, bill: bill, summary_run_id: "an-older-run")
      allow(claude_adapter).to receive(:generate_bill_summary).and_return(valid_payload)

      described_class.perform_now(bill.id)

      expect(BillSummaryPromptSnapshot.where(bill_id: bill.id).count).to eq(1)
      expect(bill.reload.bill_summary_prompt_snapshot.summary_run_id).not_to eq("an-older-run")
    end
  end

  describe "a run whose summary is refused" do
    it "records nothing when a paste supersedes the answer mid-flight" do
      allow(claude_adapter).to receive(:generate_bill_summary) do
        PasteSummaryService.new(
          bill: Bill.find(bill.id), actor: create(:user),
          summary_json: {summary_markdown: "## Pasted while the call was in flight"}.to_json
        ).call
        valid_payload
      end

      described_class.perform_now(bill.id)

      expect(bill.reload.bill_summary_prompt_snapshot).to be_nil
    end

    it "clears the earlier record too, because the paste that won read none of it" do
      create(:bill_summary_prompt_snapshot, bill: bill, summary_run_id: "an-older-run")
      allow(claude_adapter).to receive(:generate_bill_summary) do
        PasteSummaryService.new(
          bill: Bill.find(bill.id), actor: create(:user),
          summary_json: {summary_markdown: "## Pasted while the call was in flight"}.to_json
        ).call
        valid_payload
      end

      described_class.perform_now(bill.id)

      expect(bill.reload.bill_summary_prompt_snapshot).to be_nil
    end
  end

  # @lat: [[news-summary#Grounding bill summaries in approved news evidence]]
  describe "news article evidence grounding and snapshotting" do
    let(:text_version_approved) do
      create(:news_article_text_version, :extracted, text: "The city council voted 12-2 to approve the affordable housing mandate.")
    end
    let(:news_article_approved) { text_version_approved.news_article }
    let!(:bna_approved_direct) do
      create(:bill_news_article, :approved,
        bill: bill,
        news_article: news_article_approved,
        current_text_version: text_version_approved,
        match_kind: "direct")
    end

    let(:text_version_context) do
      create(:news_article_text_version, :extracted, text: "Regional housing trends show declining affordability across districts.")
    end
    let(:news_article_context) { text_version_context.news_article }
    let!(:bna_approved_context) do
      create(:bill_news_article, :approved,
        bill: bill,
        news_article: news_article_context,
        current_text_version: text_version_context,
        match_kind: "context")
    end

    let!(:bna_textless) do
      create(:bill_news_article, :approved,
        bill: bill,
        current_text_version: nil,
        match_kind: "direct")
    end

    let(:text_version_unapproved) do
      create(:news_article_text_version, :extracted, text: "An unapproved article text that should never appear.")
    end
    let!(:bna_unapproved) do
      create(:bill_news_article,
        approved: false,
        bill: bill,
        news_article: text_version_unapproved.news_article,
        current_text_version: text_version_unapproved,
        match_kind: "direct")
    end

    let(:text_version_paywalled) do
      create(:news_article_text_version, :paywalled)
    end
    let!(:bna_paywalled) do
      create(:bill_news_article, :approved,
        bill: bill,
        news_article: text_version_paywalled.news_article,
        current_text_version: text_version_paywalled,
        match_kind: "direct")
    end

    let(:valid_grounded_payload) do
      {
        "summary_markdown" => "The council approved the housing mandate [The Baltimore Banner](#{news_article_approved.canonical_url}).",
        "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
        "news_usage" => "cited",
        "cited_news_urls" => [news_article_approved.canonical_url],
        "source_uses" => [
          {
            "bill_news_article_id" => bna_approved_direct.id,
            "text_version_id" => text_version_approved.id,
            "claim_text" => "The council approved the housing mandate",
            "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
            "citation_url" => news_article_approved.canonical_url
          }
        ]
      }
    end

    it "injects only eligible_for_synthesis articles, formats bounded text with match labels and metadata inside boundary, captures snapshot, and persists draft revision with pending source uses" do
      sent_prompt = nil
      allow(claude_adapter).to receive(:generate_bill_summary) do |prompt:, **|
        sent_prompt = prompt.user_message
        valid_grounded_payload
      end
      allow(claude_adapter).to receive(:generate_news_claim_grounding).and_return(
        "verdict" => "supported",
        "reason" => "Claim directly matches excerpt"
      )

      described_class.perform_now(bill.id)

      expect(sent_prompt).to include("<news_sources>")
      expect(sent_prompt).to include("[Direct bill coverage]")
      expect(sent_prompt).to include("[Surrounding issue context]")
      expect(sent_prompt).to include("bill_news_article_id=\"#{bna_approved_direct.id}\"")
      expect(sent_prompt).to include("text_version_id=\"#{text_version_approved.id}\"")
      expect(sent_prompt).to include(news_article_approved.outlet_name)
      expect(sent_prompt).to include(news_article_approved.canonical_url)
      expect(sent_prompt).to include(news_article_approved.title)
      expect(sent_prompt).to include("voted 12-2 to approve the affordable housing mandate")
      expect(sent_prompt).to include("Regional housing trends show declining affordability across districts.")
      expect(sent_prompt).not_to include("bill_news_article_id=\"#{bna_textless.id}\"")
      expect(sent_prompt).not_to include("An unapproved article text that should never appear.")
      expect(sent_prompt).not_to include("bill_news_article_id=\"#{bna_paywalled.id}\"")

      snapshot = NewsArticleSourceSnapshot.find_by!(bill: bill, purpose: "summary")
      expect(snapshot).not_to be_nil
      captured_bna_ids = snapshot.captured_source_entries.pluck("bill_news_article_id")
      expect(captured_bna_ids).to contain_exactly(bna_approved_direct.id, bna_approved_context.id)

      revision = bill.bill_summary_revisions.order(created_at: :desc).first!
      expect(revision.news_source_snapshot_id).to eq(snapshot.id)
      expect(revision.publication_role).to eq("draft")
      expect(bill.reload.summary).not_to eq(valid_grounded_payload["summary_markdown"])

      source_use = snapshot.news_article_source_uses.first!
      expect(source_use).not_to be_nil
      expect(source_use.claim_text).to eq("The council approved the housing mandate")
      expect(source_use.evidence_excerpt).to eq("voted 12-2 to approve the affordable housing mandate")
      expect(source_use.grounding_status).to be_in(%w[pending supported])

      admin = create(:user, :sway_admin)
      bna_approved_direct.withdraw_approval!(by: admin)
      comparison = snapshot.current_eligibility_comparison
      expect(comparison.eligible?).to be(false)
      expect(comparison.stale_reasons).to include(:approval_withdrawn)
    end

    it "rejects source uses with hallucinated or cross-bill bill_news_article_id without publishing or partial subset creation" do
      bill.update!(summary: Bill::SUMMARY_PLACEHOLDER)
      other_bill = create(:bill, extracted_text: "Other bill text")
      other_art = create(:news_article, canonical_url: "https://example.com/other-bill-article")
      other_tv = create(:news_article_text_version, :extracted, news_article: other_art, text: "Other bill article excerpt text.")
      foreign_bna = create(:bill_news_article, :approved, bill: other_bill, news_article: other_art, current_text_version: other_tv)

      payload_with_invalid_uses = {
        "summary_markdown" => "The council approved the housing mandate [The Baltimore Banner](#{news_article_approved.canonical_url}).",
        "full_breakdown_markdown" => "## Section 1\nHousing mandate details.",
        "news_usage" => "cited",
        "cited_news_urls" => [news_article_approved.canonical_url],
        "source_uses" => [
          {
            "bill_news_article_id" => 999_999,
            "text_version_id" => text_version_approved.id,
            "claim_text" => "Hallucinated claim text",
            "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
            "citation_url" => news_article_approved.canonical_url
          },
          {
            "bill_news_article_id" => foreign_bna.id,
            "text_version_id" => other_tv.id,
            "claim_text" => "Cross-bill claim text",
            "evidence_excerpt" => "Other bill article excerpt text.",
            "citation_url" => other_art.canonical_url
          },
          {
            "bill_news_article_id" => bna_approved_direct.id,
            "text_version_id" => text_version_approved.id,
            "claim_text" => "The council approved the housing mandate",
            "evidence_excerpt" => "voted 12-2 to approve the affordable housing mandate",
            "citation_url" => news_article_approved.canonical_url
          }
        ]
      }

      allow(claude_adapter).to receive(:generate_bill_summary).and_return(payload_with_invalid_uses)

      expect {
        described_class.perform_now(bill.id)
      }.not_to raise_error

      snapshot = NewsArticleSourceSnapshot.find_by!(bill: bill, purpose: "summary")
      expect(snapshot.source_uses.count).to eq(0)

      revision = bill.bill_summary_revisions.order(created_at: :desc).first!
      expect(revision.publication_role).to eq("draft")
      expect(revision.news_source_snapshot_id).to eq(snapshot.id)
      expect(provisioning.reload.generation_error).to be_present
    end

    it "modifying article text after batch submission does not alter the historical batch snapshot" do
      model = "claude-3-5-sonnet"
      active_cats = [] #: Array[Category]

      SummaryBatchItem.build(
        bill: bill,
        answer_type: SummaryBatchItem::SUMMARY,
        model: model,
        active_categories: active_cats
      )

      snapshot = bill.news_article_source_snapshots.for_summary.order(created_at: :desc).first!
      expect(snapshot).not_to be_nil
      initial_entry = snapshot.captured_source_entries.find { |e| e["bill_news_article_id"] == bna_approved_direct.id }
      expect(initial_entry["text_version_id"]).to eq(text_version_approved.id)
      initial_digest = initial_entry["text_digest"]

      new_tv = create(:news_article_text_version, :extracted,
        news_article: news_article_approved,
        text: "Brand new modified text that was updated after batch submission.")
      bna_approved_direct.update!(current_text_version: new_tv)

      snapshot.reload
      reloaded_entry = snapshot.captured_source_entries.find { |e| e["bill_news_article_id"] == bna_approved_direct.id }
      expect(reloaded_entry["text_version_id"]).to eq(text_version_approved.id)
      expect(reloaded_entry["text_digest"]).to eq(initial_digest)

      comparison = snapshot.current_eligibility_comparison
      expect(comparison.eligible?).to be(false)
      expect(comparison.stale_reasons).to include(:text_version_replaced)
    end
  end
end
