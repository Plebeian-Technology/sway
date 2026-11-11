# frozen_string_literal: true

require "rails_helper"

RSpec.describe ManualNewsSummaryPublicationService do
  let(:grounding_adapter) do
    double("news claim grounding adapter", generate_news_claim_grounding: {"verdict" => "supported", "reason" => "Fixture grounding response"})
  end

  before do
    allow(Llm::Client).to receive(:build).and_return(grounding_adapter)
  end

  let(:sway_locale) { create(:sway_locale) }
  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill, sway_locale: sway_locale, summary: "Pristine starting summary", link: "https://legistar.baltimorecity.gov/LegislationDetail.aspx?ID=123") }
  let(:news_article) { create(:news_article, canonical_url: "https://baltimorebanner.com/story") }
  let(:text_version) { create(:news_article_text_version, :extracted, news_article: news_article, text: "The city council approved 50 new parks.") }

  describe ".publish!" do
    context "when news_usage is missing or invalid" do
      it "returns :missing_news_usage, leaves bill.summary unchanged, and records a draft revision" do
        result = described_class.publish!(
          bill: bill,
          summary_markdown: "New summary without declaration",
          actor: admin,
          news_usage: nil
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:missing_news_usage)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
        expect(result.revision.summary_markdown).to eq("New summary without declaration")
      end

      it "rejects unrecognized news_usage string like 'unspecified'" do
        result = described_class.publish!(
          bill: bill,
          summary_markdown: "New summary with bad declaration",
          actor: admin,
          news_usage: "unspecified"
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:missing_news_usage)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end
    end

    context "when news_usage is 'none'" do
      it "publishes clean text and creates a published revision without snapshot" do
        result = described_class.publish!(
          bill: bill,
          summary_markdown: "Clean summary without any news reporting.",
          actor: admin,
          news_usage: "none"
        )

        expect(result.published?).to be(true)
        expect(result.status).to eq(:published)
        expect(bill.reload.summary).to eq("Clean summary without any news reporting.")
        expect(result.revision.publication_role).to eq("published")
        expect(result.revision.news_source_snapshot_id).to be_nil
      end

      it "allows official legislative bill.link in prose" do
        result = described_class.publish!(
          bill: bill,
          summary_markdown: "See official text at [Legistar](#{bill.link}) for details.",
          actor: admin,
          news_usage: "none"
        )

        expect(result.published?).to be(true)
        expect(bill.reload.summary).to eq("See official text at [Legistar](#{bill.link}) for details.")
        expect(result.revision.publication_role).to eq("published")
      end

      it "refuses publication when visible news citations exist in prose" do
        result = described_class.publish!(
          bill: bill,
          summary_markdown: "Summary citing [Banner](https://baltimorebanner.com/story).",
          actor: admin,
          news_usage: "none"
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:invalid_news_usage)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end

      it "refuses publication when source_uses manifest is provided with none declaration" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        result = described_class.publish!(
          bill: bill,
          summary_markdown: "Summary declaring none but providing sources.",
          actor: admin,
          news_usage: "none",
          source_uses: [{bill_news_article_id: approved_bna.id}]
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:invalid_news_usage)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end
    end

    context "when news_usage is 'cited'" do
      it "refuses publication when source_uses is empty" do
        result = described_class.publish!(
          bill: bill,
          summary_markdown: "Summary claiming cited news.",
          actor: admin,
          news_usage: "cited",
          source_uses: []
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:empty_source_uses)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end

      it "refuses publication when cited article is unapproved" do
        unapproved_bna = create(:bill_news_article, approved: false, bill: bill, news_article: news_article, current_text_version: text_version)

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "The city council approved 50 new parks [Source](https://baltimorebanner.com/story).",
          actor: admin,
          news_usage: "cited",
          source_uses: [
            {
              bill_news_article_id: unapproved_bna.id,
              text_version_id: text_version.id,
              claim_text: "The city council approved 50 new parks",
              evidence_excerpt: "The city council approved 50 new parks.",
              citation_url: "https://baltimorebanner.com/story"
            }
          ]
        )

        expect(result.published?).to be(false)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end

      it "refuses publication when cited article belongs to another bill" do
        other_bill = create(:bill, sway_locale: sway_locale)
        foreign_bna = create(:bill_news_article, :approved, bill: other_bill, news_article: news_article, current_text_version: text_version)

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "The city council approved 50 new parks [Source](https://baltimorebanner.com/story).",
          actor: admin,
          news_usage: "cited",
          source_uses: [
            {
              bill_news_article_id: foreign_bna.id,
              text_version_id: text_version.id,
              claim_text: "The city council approved 50 new parks",
              evidence_excerpt: "The city council approved 50 new parks.",
              citation_url: "https://baltimorebanner.com/story"
            }
          ]
        )

        expect(result.published?).to be(false)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end

      it "publishes valid cited summary, captures snapshot, and records published revision with snapshot" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "#{claim_text} [Source](#{url}).",
          actor: admin,
          news_usage: "cited",
          source_uses: [
            {
              bill_news_article_id: approved_bna.id,
              text_version_id: text_version.id,
              claim_text: claim_text,
              evidence_excerpt: excerpt,
              citation_url: url
            }
          ]
        )

        expect(result.published?).to be(true)
        expect(bill.reload.summary).to eq("#{claim_text} [Source](#{url}).")
        expect(result.revision.publication_role).to eq("published")
        expect(result.revision.news_source_snapshot_id).to be_present
        expect(result.snapshot).to eq(result.revision.news_source_snapshot)
        expect(result.snapshot.source_uses.count).to eq(1)
      end

      it "publishes cited summary with markdown links to approved news articles when source_uses is empty" do
        article1 = create(:news_article, canonical_url: "https://marylandmatters.org/2026/02/24/house-committee-takes-up-bill-that-would-ban-masks-on-police-immigration-agents/")
        tv1 = create(:news_article_text_version, :extracted, news_article: article1, text: "The measure passed the full Senate on a 31-13 vote.")
        bna1 = create(:bill_news_article, :approved, bill: bill, news_article: article1, current_text_version: tv1)

        article2 = create(:news_article, canonical_url: "https://marylandmatters.org/2026/01/28/senate-panel-advances-bills-to-ban-agreements-with-ice-face-coverings-for-law-enforcement/")
        tv2 = create(:news_article_text_version, :extracted, news_article: article2, text: "Approved by the Senate Judicial Proceedings Committee.")
        bna2 = create(:bill_news_article, :approved, bill: bill, news_article: article2, current_text_version: tv2)

        markdown = "Maryland Senate Bill 1 prohibits sworn law enforcement officers from wearing opaque face coverings while on duty in the state, except under specific authorized circumstances. Originating in the Maryland Senate, the bill is listed in committee in official records, though [Maryland Matters](#{article1.canonical_url}) reported that the measure passed the full Senate on a 31-13 vote after being approved by the Senate Judicial Proceedings Committee, according to earlier reporting by [Maryland Matters](#{article2.canonical_url})."

        result = described_class.publish!(
          bill: bill,
          summary_markdown: markdown,
          actor: admin,
          news_usage: "cited",
          source_uses: []
        )

        expect(result.published?).to be(true)
        expect(result.errors).to be_empty
        expect(bill.reload.summary).to eq(markdown)
        expect(result.revision.publication_role).to eq("published")
        expect(result.revision.news_source_snapshot_id).to be_present
        expect(result.snapshot.captured_source_entries.pluck("bill_news_article_id")).to match_array([bna1.id, bna2.id])
      end
    end

    context "when origin is restoration" do
      it "restores revision with eligible snapshot as published" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"

        snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "summary",
          actor: admin,
          sources: [approved_bna],
          source_uses_attributes: [
            {
              bill_news_article_id: approved_bna.id,
              text_version_id: text_version.id,
              claim_text: claim_text,
              evidence_excerpt: excerpt,
              citation_url: url
            }
          ]
        )
        news_rev = BillSummaryRevision.record_revision!(
          bill: bill,
          summary_markdown: "News summary text: #{claim_text} [Report](#{url}).",
          origin: "model_generation",
          publication_role: "published",
          review_state: "reviewed",
          news_source_snapshot: snapshot
        )

        result = described_class.publish!(
          bill: bill,
          summary_markdown: news_rev.summary_markdown,
          actor: admin,
          origin: "restoration",
          snapshot: snapshot,
          restored_from: news_rev
        )

        expect(result.published?).to be(true)
        expect(bill.reload.summary).to eq(news_rev.summary_markdown)
        expect(result.revision.publication_role).to eq("published")
        expect(result.revision.news_source_snapshot_id).to eq(snapshot.id)
      end

      it "refuses public restoration when snapshot approval was withdrawn and saves draft revision" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "summary",
          actor: admin,
          sources: [approved_bna]
        )
        news_rev = BillSummaryRevision.record_revision!(
          bill: bill,
          summary_markdown: "News summary text citing [Report](https://baltimorebanner.com/story).",
          origin: "model_generation",
          publication_role: "published",
          review_state: "reviewed",
          news_source_snapshot: snapshot
        )

        approved_bna.withdraw_approval!(by: admin)

        result = described_class.publish!(
          bill: bill,
          summary_markdown: news_rev.summary_markdown,
          actor: admin,
          origin: "restoration",
          snapshot: snapshot,
          restored_from: news_rev
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:stale_version_lock)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end

      it "restores snapshotless revision with news links as review draft without altering bill.summary" do
        legacy_news_rev = BillSummaryRevision.record_revision!(
          bill: bill,
          summary_markdown: "Legacy text citing [Banner](https://baltimorebanner.com/story).",
          origin: "model_generation",
          publication_role: "published",
          review_state: "reviewed",
          news_source_snapshot: nil
        )

        result = described_class.publish!(
          bill: bill,
          summary_markdown: legacy_news_rev.summary_markdown,
          actor: admin,
          origin: "restoration",
          snapshot: nil,
          restored_from: legacy_news_rev
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:review_draft)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end

      it "restores clean snapshotless non-news revision as review draft when news_usage is omitted" do
        legacy_clean_rev = BillSummaryRevision.record_revision!(
          bill: bill,
          summary_markdown: "Legacy text without any news reporting links.",
          origin: "operator_edit",
          publication_role: "published",
          review_state: "reviewed",
          news_source_snapshot: nil
        )

        result = described_class.publish!(
          bill: bill,
          summary_markdown: legacy_clean_rev.summary_markdown,
          actor: admin,
          origin: "restoration",
          snapshot: nil,
          restored_from: legacy_clean_rev
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:review_draft)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end

      it "restores clean snapshotless non-news revision as published when news_usage is explicitly 'none'" do
        legacy_clean_rev = BillSummaryRevision.record_revision!(
          bill: bill,
          summary_markdown: "Legacy text without any news reporting links.",
          origin: "operator_edit",
          publication_role: "published",
          review_state: "reviewed",
          news_source_snapshot: nil
        )

        result = described_class.publish!(
          bill: bill,
          summary_markdown: legacy_clean_rev.summary_markdown,
          actor: admin,
          origin: "restoration",
          news_usage: "none",
          snapshot: nil,
          restored_from: legacy_clean_rev
        )

        expect(result.published?).to be(true)
        expect(bill.reload.summary).to eq("Legacy text without any news reporting links.")
        expect(result.revision.publication_role).to eq("published")
      end

      it "refuses restoration when news_usage is 'none' but prose cites news reporting" do
        legacy_news_rev = BillSummaryRevision.record_revision!(
          bill: bill,
          summary_markdown: "Legacy summary citing [Reporting](https://baltimorebanner.com/story).",
          origin: "operator_edit",
          publication_role: "published",
          review_state: "reviewed",
          news_source_snapshot: nil
        )

        result = described_class.publish!(
          bill: bill,
          summary_markdown: legacy_news_rev.summary_markdown,
          actor: admin,
          origin: "restoration",
          news_usage: "none",
          snapshot: nil,
          restored_from: legacy_news_rev
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:invalid_news_usage)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end
    end

    context "when dry_run is true" do
      it "evaluates validation without modifying bill.summary or creating revisions" do
        initial_rev_count = bill.bill_summary_revisions.count

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "Valid clean summary on dry run.",
          actor: admin,
          news_usage: "none",
          dry_run: true
        )

        expect(result.published?).to be(true)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(bill.bill_summary_revisions.count).to eq(initial_rev_count)
        expect(result.revision).to be_nil
      end

      it "does not persist snapshots or source uses when validating cited news usage" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"

        expect do
          result = described_class.publish!(
            bill: bill,
            summary_markdown: "#{claim_text} [Source](#{url}).",
            actor: admin,
            news_usage: "cited",
            source_uses: [
              {
                bill_news_article_id: approved_bna.id,
                text_version_id: text_version.id,
                claim_text: claim_text,
                evidence_excerpt: excerpt,
                citation_url: url
              }
            ],
            dry_run: true
          )

          expect(result.published?).to be(true)
          expect(result.revision).to be_nil
        end.not_to change(NewsArticleSourceSnapshot, :count)

        expect(NewsArticleSourceUse.count).to eq(0)
        expect(bill.bill_summary_revisions.count).to eq(0)
        expect(bill.reload.summary).to eq("Pristine starting summary")
      end
    end

    context "when assessment response changes between first check and final persistence" do
      it "in manual edit: refuses publication and retains draft when second assessment returns unsupported" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"
        valid_uses = [
          {
            bill_news_article_id: approved_bna.id,
            text_version_id: text_version.id,
            claim_text: claim_text,
            evidence_excerpt: excerpt,
            citation_url: url
          }
        ]

        call_count = 0
        allow(NewsClaimGroundingService).to receive(:call).and_wrap_original do |original, **kwargs|
          call_count += 1
          if call_count == 1
            original.call(**kwargs)
          else
            NewsClaimGroundingService::Result.new(
              verdict: "unsupported",
              deterministic_errors: ["Contradiction detected in final evidence binding"]
            )
          end
        end

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "#{claim_text} [Source](#{url}).",
          actor: admin,
          news_usage: "cited",
          source_uses: valid_uses
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:unsupported_grounding)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
        expect(result.errors).to include("Contradiction detected in final evidence binding")
      end

      it "in manual edit: refuses publication and retains draft when second assessment returns indeterminate" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"
        valid_uses = [
          {
            bill_news_article_id: approved_bna.id,
            text_version_id: text_version.id,
            claim_text: claim_text,
            evidence_excerpt: excerpt,
            citation_url: url
          }
        ]

        call_count = 0
        allow(NewsClaimGroundingService).to receive(:call).and_wrap_original do |original, **kwargs|
          call_count += 1
          if call_count == 1
            original.call(**kwargs)
          else
            NewsClaimGroundingService::Result.new(
              verdict: "indeterminate",
              deterministic_errors: ["Verification timeout in second assessment"]
            )
          end
        end

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "#{claim_text} [Source](#{url}).",
          actor: admin,
          news_usage: "cited",
          source_uses: valid_uses
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:indeterminate_grounding)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
        expect(result.errors).to include("Verification timeout in second assessment")
      end

      it "in legacy restoration: refuses publication and retains draft when second assessment returns unsupported" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"
        valid_uses = [
          {
            bill_news_article_id: approved_bna.id,
            text_version_id: text_version.id,
            claim_text: claim_text,
            evidence_excerpt: excerpt,
            citation_url: url
          }
        ]

        legacy_news_rev = BillSummaryRevision.record_revision!(
          bill: bill,
          summary_markdown: "#{claim_text} [Source](#{url}).",
          origin: "model_generation",
          publication_role: "published",
          review_state: "reviewed",
          news_source_snapshot: nil
        )

        call_count = 0
        allow(NewsClaimGroundingService).to receive(:call).and_wrap_original do |original, **kwargs|
          call_count += 1
          if call_count == 1
            original.call(**kwargs)
          else
            NewsClaimGroundingService::Result.new(
              verdict: "unsupported",
              deterministic_errors: ["Legacy claims unsupported on final binding"]
            )
          end
        end

        result = described_class.publish!(
          bill: bill,
          summary_markdown: legacy_news_rev.summary_markdown,
          actor: admin,
          origin: "restoration",
          news_usage: "cited",
          source_uses: valid_uses,
          snapshot: nil,
          restored_from: legacy_news_rev
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:unsupported_grounding)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
        expect(result.errors).to include("Legacy claims unsupported on final binding")
      end

      it "in legacy restoration: refuses publication and retains draft when second assessment returns indeterminate" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"
        valid_uses = [
          {
            bill_news_article_id: approved_bna.id,
            text_version_id: text_version.id,
            claim_text: claim_text,
            evidence_excerpt: excerpt,
            citation_url: url
          }
        ]

        legacy_news_rev = BillSummaryRevision.record_revision!(
          bill: bill,
          summary_markdown: "#{claim_text} [Source](#{url}).",
          origin: "model_generation",
          publication_role: "published",
          review_state: "reviewed",
          news_source_snapshot: nil
        )

        call_count = 0
        allow(NewsClaimGroundingService).to receive(:call).and_wrap_original do |original, **kwargs|
          call_count += 1
          if call_count == 1
            original.call(**kwargs)
          else
            NewsClaimGroundingService::Result.new(
              verdict: "indeterminate",
              deterministic_errors: ["Legacy claims indeterminate on final binding"]
            )
          end
        end

        result = described_class.publish!(
          bill: bill,
          summary_markdown: legacy_news_rev.summary_markdown,
          actor: admin,
          origin: "restoration",
          news_usage: "cited",
          source_uses: valid_uses,
          snapshot: nil,
          restored_from: legacy_news_rev
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:indeterminate_grounding)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
        expect(result.errors).to include("Legacy claims indeterminate on final binding")
      end
    end

    context "when article approval or text version is invalidated before final commit" do
      it "refuses publication when approval is withdrawn right before commit" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"
        valid_uses = [
          {
            bill_news_article_id: approved_bna.id,
            text_version_id: text_version.id,
            claim_text: claim_text,
            evidence_excerpt: excerpt,
            citation_url: url
          }
        ]

        allow(NewsClaimGroundingService).to receive(:call).and_wrap_original do |original, **kwargs|
          res = original.call(**kwargs)
          approved_bna.withdraw_approval!(by: admin) if kwargs[:persist] == true
          res
        end

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "#{claim_text} [Source](#{url}).",
          actor: admin,
          news_usage: "cited",
          source_uses: valid_uses
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:stale_version_lock)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end

      it "refuses publication when text version changes right before commit" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"
        valid_uses = [
          {
            bill_news_article_id: approved_bna.id,
            text_version_id: text_version.id,
            claim_text: claim_text,
            evidence_excerpt: excerpt,
            citation_url: url
          }
        ]

        allow(NewsClaimGroundingService).to receive(:call).and_wrap_original do |original, **kwargs|
          res = original.call(**kwargs)
          if kwargs[:persist] == true
            newer_text = create(:news_article_text_version, :extracted, news_article: news_article, text: "Different text entirely.")
            approved_bna.update!(current_text_version: newer_text)
          end
          res
        end

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "#{claim_text} [Source](#{url}).",
          actor: admin,
          news_usage: "cited",
          source_uses: valid_uses
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:stale_version_lock)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end

      it "refuses publication when summary contains only an unused reference definition" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"
        valid_uses = [
          {
            bill_news_article_id: approved_bna.id,
            text_version_id: text_version.id,
            claim_text: claim_text,
            evidence_excerpt: excerpt,
            citation_url: url
          }
        ]

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "#{claim_text}\n\n[source]: #{url}",
          actor: admin,
          news_usage: "cited",
          source_uses: valid_uses
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:unsupported_grounding)
        expect(bill.reload.summary).to eq("Pristine starting summary")
        expect(result.revision.publication_role).to eq("draft")
      end

      it "permits publication when summary contains a used reference-style link" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        excerpt = "The city council approved 50 new parks."
        url = "https://baltimorebanner.com/story"
        valid_uses = [
          {
            bill_news_article_id: approved_bna.id,
            text_version_id: text_version.id,
            claim_text: claim_text,
            evidence_excerpt: excerpt,
            citation_url: url
          }
        ]

        allow(NewsClaimGroundingService).to receive(:call).and_wrap_original do |original, **kwargs|
          original.call(**kwargs)
          NewsClaimGroundingService::Result.new(
            verdict: "supported",
            claim_assessments: [
              NewsClaimGroundingService::ClaimAssessment.new(
                claim_text: claim_text,
                evidence_excerpt: excerpt,
                citation_url: url,
                bill_news_article_id: approved_bna.id,
                text_version_id: text_version.id,
                verdict: "supported",
                reason: "Supported",
                phase: :semantic
              )
            ]
          )
        end

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "#{claim_text} [Source][source]\n\n[source]: #{url}",
          actor: admin,
          news_usage: "cited",
          source_uses: valid_uses
        )

        expect(result.published?).to be(true)
        expect(result.status).to eq(:published)
        expect(bill.reload.summary).to eq("#{claim_text} [Source][source]\n\n[source]: #{url}")
        expect(result.revision.publication_role).to eq("published")
      end

      it "handles ActionController::Parameters source_uses with string keys" do
        approved_bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)
        claim_text = "The city council approved 50 new parks"
        url = "https://baltimorebanner.com/story"
        string_keyed_uses = ActionController::Parameters.new(
          uses: [
            {
              "bill_news_article_id" => approved_bna.id,
              "text_version_id" => text_version.id,
              "claim_text" => claim_text,
              "evidence_excerpt" => "The city council approved 50 new parks.",
              "citation_url" => url
            }
          ]
        ).require(:uses)

        allow(NewsClaimGroundingService).to receive(:call).and_wrap_original do |original, **kwargs|
          original.call(**kwargs)
          NewsClaimGroundingService::Result.new(
            verdict: "supported",
            claim_assessments: [
              NewsClaimGroundingService::ClaimAssessment.new(
                claim_text: claim_text,
                evidence_excerpt: "The city council approved 50 new parks.",
                citation_url: url,
                bill_news_article_id: approved_bna.id,
                text_version_id: text_version.id,
                verdict: "supported",
                reason: "Supported",
                phase: :semantic
              )
            ]
          )
        end

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "#{claim_text} [Source](#{url}).",
          actor: admin,
          news_usage: "cited",
          source_uses: string_keyed_uses
        )

        expect(result.published?).to be(true)
        expect(result.revision.publication_role).to eq("published")
        expect(result.snapshot.source_uses.count).to eq(1)
      end

      it "refuses restoration when snapshot belongs to a different bill" do
        other_bill = create(:bill, sway_locale: sway_locale)
        other_bna = create(:bill_news_article, :approved, bill: other_bill, news_article: news_article, current_text_version: text_version)
        foreign_snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: other_bill,
          purpose: "summary",
          actor: admin,
          sources: [other_bna]
        )

        result = described_class.publish!(
          bill: bill,
          summary_markdown: "Attempting to restore foreign snapshot.",
          actor: admin,
          origin: "restoration",
          snapshot: foreign_snapshot
        )

        expect(result.published?).to be(false)
        expect(result.status).to eq(:invalid_news_usage)
        expect(result.errors).to include("Snapshot does not belong to bill")
      end

      it "preserves initial baseline revision on failed manual edit if bill had pristine summary and no prior revisions" do
        fresh_bill = create(:bill, sway_locale: sway_locale, summary: "Pristine initial baseline summary")
        expect(fresh_bill.bill_summary_revisions.count).to eq(0)

        result = described_class.publish!(
          bill: fresh_bill,
          summary_markdown: "Malformed update without declaration",
          actor: admin,
          news_usage: nil
        )

        expect(result.published?).to be(false)
        expect(fresh_bill.reload.summary).to eq("Pristine initial baseline summary")

        revisions = fresh_bill.bill_summary_revisions.order(:id)
        expect(revisions.count).to eq(2)
        expect(revisions.first.origin).to eq("initial_baseline")
        expect(revisions.first.publication_role).to eq("published")
        expect(revisions.first.summary_markdown).to eq("Pristine initial baseline summary")
        expect(revisions.second.publication_role).to eq("draft")
        expect(revisions.second.summary_markdown).to eq("Malformed update without declaration")
      end
    end
  end
end
