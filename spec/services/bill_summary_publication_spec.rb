# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Whose words a stored summary records]]
RSpec.describe BillSummaryPublication do
  describe ".publishable?" do
    it "publishes over an empty summary" do
      bill = build(:bill, summary: "")

      expect(described_class.publishable?(bill: bill, previous_draft: nil)).to be(true)
    end

    it "publishes over whitespace, which shows a reader nothing" do
      bill = build(:bill, summary: "   \n ")

      expect(described_class.publishable?(bill: bill, previous_draft: nil)).to be(true)
    end

    it "publishes over the ingestion placeholder" do
      bill = build(:bill, summary: Bill::SUMMARY_PLACEHOLDER)

      expect(described_class.publishable?(bill: bill, previous_draft: nil)).to be(true)
    end

    it "publishes over the draft an earlier run published" do
      bill = build(:bill, summary: "The last run wrote this.")

      expect(
        described_class.publishable?(bill: bill, previous_draft: "The last run wrote this.")
      ).to be(true)
    end

    # The C21-02 rule. A save once put the model's draft over an admin's words
    # under a green success message; auto-publish must not reopen that.
    it "refuses to publish over text a person wrote" do
      bill = build(:bill, summary: "An admin wrote this by hand.")

      expect(
        described_class.publishable?(bill: bill, previous_draft: "The last run wrote something else.")
      ).to be(false)
    end

    # The published text and the draft disagree here in the other direction:
    # a person wrote the summary and there has never been a draft at all.
    it "refuses when a person wrote the summary and no draft preceded it" do
      bill = build(:bill, summary: "An admin wrote this by hand.")

      expect(described_class.publishable?(bill: bill, previous_draft: nil)).to be(false)
    end
  end

  describe ".evaluate generated news publication on validated evidence" do
    let(:sway_locale) { create(:sway_locale) }
    let(:bill) { create(:bill, sway_locale: sway_locale).tap { |b| b.update_columns(summary: "") } }
    let(:news_article) { create(:news_article, canonical_url: "https://example.com/story") }
    let(:text_version) { create(:news_article_text_version, :extracted, news_article: news_article, text: "Council voted 12-2 to approve the measure.") }
    let(:bna) { create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version) }
    let!(:snapshot) do
      NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "summary",
        run_receipt: "receipt-eval-1",
        sources: [bna]
      )
    end

    it "publishes when news_usage is 'none' and no news URLs exist in prose" do
      decision = described_class.evaluate(
        bill: bill,
        previous_draft: nil,
        content: "Council voted to approve the measure.",
        news_usage: "none",
        snapshot: nil
      )

      expect(decision.publishable?).to be(true)
      expect(decision.status).to eq(:publishable)
      expect(decision.errors).to be_empty
    end

    it "refuses publication when news_usage is 'none' but prose contains visible news citations" do
      decision = described_class.evaluate(
        bill: bill,
        previous_draft: nil,
        content: "Council voted to approve [News Story](https://baltimoresun.com/story).",
        news_usage: "none",
        snapshot: nil
      )

      expect(decision.publishable?).to be(false)
      expect(decision.status).to eq(:invalid_news_usage)
      expect(decision.errors.join).to include("Declared no-news usage but content contains visible news citations")
    end

    it "publishes when news_usage is 'cited', claims are supported, and versions are fresh" do
      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        verdict: "supported",
        errors: []
      )

      decision = described_class.evaluate(
        bill: bill,
        previous_draft: nil,
        content: "Council voted 12-2 [Story](https://example.com/story).",
        news_usage: "cited",
        snapshot: snapshot,
        grounding_result: supported_grounding
      )

      expect(decision.publishable?).to be(true)
      expect(decision.status).to eq(:publishable)
      expect(decision.errors).to be_empty
    end

    it "refuses publication when cited news claims fail grounding (verdict: unsupported)" do
      unsupported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: false,
        unsupported?: true,
        indeterminate?: false,
        verdict: "unsupported",
        errors: ["Claim 'Council voted 15-0' contradicts source text"]
      )

      decision = described_class.evaluate(
        bill: bill,
        previous_draft: nil,
        content: "Council voted 15-0 [Story](https://example.com/story).",
        news_usage: "cited",
        snapshot: snapshot,
        grounding_result: unsupported_grounding
      )

      expect(decision.publishable?).to be(false)
      expect(decision.status).to eq(:unsupported_grounding)
      expect(decision.errors).to include("Claim 'Council voted 15-0' contradicts source text")
    end

    it "refuses publication when grounding is indeterminate (fail-closed)" do
      indeterminate_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: false,
        unsupported?: false,
        indeterminate?: true,
        verdict: "indeterminate",
        errors: ["Grounding assessment timed out"]
      )

      decision = described_class.evaluate(
        bill: bill,
        previous_draft: nil,
        content: "Council voted 12-2 [Story](https://example.com/story).",
        news_usage: "cited",
        snapshot: snapshot,
        grounding_result: indeterminate_grounding
      )

      expect(decision.publishable?).to be(false)
      expect(decision.status).to eq(:indeterminate_grounding)
      expect(decision.errors).to include("Grounding assessment timed out")
    end

    it "refuses publication when snapshot has withdrawn approval (stale version lock)" do
      bna.withdraw_approval!(by: create(:user, :sway_admin))

      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        verdict: "supported",
        errors: []
      )

      decision = described_class.evaluate(
        bill: bill,
        previous_draft: nil,
        content: "Council voted 12-2 [Story](https://example.com/story).",
        news_usage: "cited",
        snapshot: snapshot,
        grounding_result: supported_grounding
      )

      expect(decision.publishable?).to be(false)
      expect(decision.status).to eq(:stale_version_lock)
      expect(decision.reasons).to include(:approval_withdrawn)
      expect(decision.errors.join).to include("approval has been withdrawn")
    end

    it "refuses publication when snapshot text version was replaced (stale version lock)" do
      new_tv = create(
        :news_article_text_version,
        :extracted,
        news_article: news_article,
        text: "Council voted 12-2 to approve the measure with amendments."
      )
      bna.update!(current_text_version: new_tv)

      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        verdict: "supported",
        errors: []
      )

      decision = described_class.evaluate(
        bill: bill,
        previous_draft: nil,
        content: "Council voted 12-2 [Story](https://example.com/story).",
        news_usage: "cited",
        snapshot: snapshot,
        grounding_result: supported_grounding
      )

      expect(decision.publishable?).to be(false)
      expect(decision.status).to eq(:stale_version_lock)
      expect(decision.reasons).to include(:text_version_replaced)
      expect(decision.errors.join).to include("selected text version changed")
    end

    it "refuses publication when article stance changed or was cleared after snapshot capture" do
      admin = create(:user, :sway_admin)
      supported_grounding_result = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        verdict: "supported",
        errors: []
      )
      bna.set_stance!("support", by: admin)
      stance_snapshot = NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "summary",
        run_receipt: "stance-lock-run",
        sources: [bna]
      )
      bna.set_stance!("oppose", by: admin)

      decision = described_class.evaluate(
        bill: bill,
        previous_draft: nil,
        content: "Council voted [Story](https://example.com/story).",
        snapshot: stance_snapshot,
        news_usage: "cited",
        grounding_result: supported_grounding_result
      )

      expect(decision.publishable?).to be(false)
      expect(decision.status).to eq(:stale_version_lock)
      expect(decision.reasons).to include(:stance_changed)
      expect(decision.errors.join).to match(/stance changed from support to oppose/i)

      clear_snapshot = NewsArticleSourceSnapshotService.capture!(
        bill: bill,
        purpose: "summary",
        run_receipt: "stance-clear-run",
        sources: [bna]
      )
      bna.clear_stance!(by: admin)

      clear_decision = described_class.evaluate(
        bill: bill,
        previous_draft: nil,
        content: "Council voted [Story](https://example.com/story).",
        snapshot: clear_snapshot,
        news_usage: "cited",
        grounding_result: supported_grounding_result
      )

      expect(clear_decision.publishable?).to be(false)
      expect(clear_decision.status).to eq(:stale_version_lock)
      expect(clear_decision.reasons).to include(:stance_changed)
    end

    it "refuses publication when human overwrite protection applies" do
      create(
        :bill_summary_revision,
        bill: bill,
        summary_markdown: "An admin carefully curated this summary.",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed"
      )
      bill.update_columns(summary: "An admin carefully curated this summary.")

      decision = described_class.evaluate(
        bill: bill,
        previous_draft: "Different draft",
        content: "Model generated summary.",
        news_usage: "none",
        snapshot: nil
      )

      expect(decision.publishable?).to be(false)
      expect(decision.status).to eq(:operator_overwrite)
      expect(decision.reasons).to include(:operator_overwrite_blocked)
    end

    it "refuses publication when cited news usage has no snapshot" do
      decision = described_class.evaluate(
        bill: bill,
        previous_draft: nil,
        content: "Council voted [Story](https://example.com/story).",
        news_usage: "cited",
        snapshot: nil
      )

      expect(decision.publishable?).to be(false)
      expect(decision.status).to eq(:missing_snapshot)
    end
  end
end
