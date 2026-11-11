# frozen_string_literal: true

require "rails_helper"

# @lat: [[news-testimony#Why published opinion is distinct from hearing submissions]]
# @lat: [[news-testimony#Why commentary attribution separates author and publisher roles]]
# @lat: [[news-testimony#Why source snapshots and draft persistence precede publication]]
# @lat: [[news-gate#Why opinion commentary is gated separately from hearing testimony]]
RSpec.describe NewsArticleTestimonyService do
  let(:sway_locale) { create(:sway_locale) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }
  let(:admin) { create(:user, :sway_admin) }

  let(:op_ed_article) do
    create(
      :news_article,
      :op_ed,
      title: "Why Council Bill 100 Deserves Full Support",
      author_name: "Jane Columnist",
      outlet_name: "The Baltimore Sun",
      canonical_url: "https://baltimoresun.com/opinion/council-bill-100-support"
    )
  end

  let(:op_ed_text_version) do
    create(
      :news_article_text_version,
      :extracted,
      news_article: op_ed_article,
      text: "Council Bill 100 provides essential housing protections that will prevent arbitrary evictions across the city."
    )
  end

  let!(:eligible_op_ed) do
    create(
      :bill_news_article,
      :approved,
      :support,
      bill: bill,
      news_article: op_ed_article,
      current_text_version: op_ed_text_version
    )
  end

  let(:snapshot) do
    NewsArticleSourceSnapshotService.capture!(
      bill: bill,
      purpose: "testimony",
      run_receipt: "test_receipt_123",
      sources: [eligible_op_ed]
    )
  end

  describe ".eligible_articles and .commentary_eligible?" do
    it "includes approved op-eds and editorials with stance and usable text" do
      editorial_article = create(:news_article, :editorial, outlet_name: "Baltimore Banner")
      editorial_tv = create(:news_article_text_version, :extracted, news_article: editorial_article, text: "Editorial board opposition text.")
      editorial_bna = create(:bill_news_article, :approved, :oppose, bill: bill, news_article: editorial_article, current_text_version: editorial_tv)

      expect(described_class.eligible_articles(bill)).to contain_exactly(eligible_op_ed, editorial_bna)
      expect(described_class.commentary_eligible?(bill)).to be true
    end

    it "strictly excludes reporting articles, even if approved with a stance" do
      reporting_article = create(:news_article, article_kind: "reporting")
      reporting_tv = create(:news_article_text_version, :extracted, news_article: reporting_article, text: "Factual reporting text.")
      create(:bill_news_article, :approved, :support, bill: bill, news_article: reporting_article, current_text_version: reporting_tv)

      expect(described_class.eligible_articles(bill)).to contain_exactly(eligible_op_ed)
    end

    it "strictly excludes textless approved op-eds" do
      textless_article = create(:news_article, :op_ed)
      create(:bill_news_article, :approved, :support, bill: bill, news_article: textless_article, current_text_version: nil)

      expect(described_class.eligible_articles(bill)).to contain_exactly(eligible_op_ed)
    end

    it "strictly excludes unapproved op-eds" do
      unapproved_article = create(:news_article, :op_ed)
      unapproved_tv = create(:news_article_text_version, :extracted, news_article: unapproved_article, text: "Some opinion text.")
      create(:bill_news_article, bill: bill, approved: false, stance: "support", news_article: unapproved_article, current_text_version: unapproved_tv)

      expect(described_class.eligible_articles(bill)).to contain_exactly(eligible_op_ed)
    end

    it "strictly excludes op-eds with no stance classified (stance: nil)" do
      no_stance_article = create(:news_article, :op_ed)
      no_stance_tv = create(:news_article_text_version, :extracted, news_article: no_stance_article, text: "Some opinion text.")
      create(:bill_news_article, :approved, bill: bill, stance: nil, news_article: no_stance_article, current_text_version: no_stance_tv)

      expect(described_class.eligible_articles(bill)).to contain_exactly(eligible_op_ed)
    end
  end

  describe ".persist_drafts!" do
    let(:verbatim_excerpt) { "Council Bill 100 provides essential housing protections" }
    let(:valid_commentary_payload) do
      {
        "draft_org_positions" => [],
        "draft_news_testimonies" => [
          {
            "bill_news_article_id" => eligible_op_ed.id,
            "text_version_id" => op_ed_text_version.id,
            "author_name" => "Jane Columnist",
            "outlet_name" => "The Baltimore Sun",
            "canonical_url" => "https://baltimoresun.com/opinion/council-bill-100-support",
            "stance" => "support",
            "argument" => "Council Bill 100 provides essential protections that strengthen tenant rights against arbitrary eviction.",
            "evidence_excerpt" => verbatim_excerpt
          }
        ]
      }
    end

    it "extracts draft NewsArticleTestimony records with exact metadata and snapshot link" do
      expect {
        described_class.persist_drafts!(
          bill: bill,
          payload: valid_commentary_payload,
          snapshot: snapshot,
          run_receipt: "receipt-1"
        )
      }.to change(NewsArticleTestimony, :count).by(1)

      testimony = NewsArticleTestimony.last!
      expect(testimony.bill_news_article).to eq(eligible_op_ed)
      expect(testimony.news_article_source_snapshot).to eq(snapshot)
      expect(testimony.news_article_text_version).to eq(op_ed_text_version)
      expect(testimony.publication_state).to eq("draft")
      expect(testimony.stance).to eq("support")
      expect(testimony.stance_version).to eq(eligible_op_ed.stance_version)
      expect(testimony.review_version).to eq(eligible_op_ed.review_version)
      expect(testimony.text_digest).to eq(op_ed_text_version.digest)
      expect(testimony.outlet_name).to eq("The Baltimore Sun")
      expect(testimony.author_name).to eq("Jane Columnist")
      expect(testimony.citation_url).to eq("https://baltimoresun.com/opinion/council-bill-100-support")
      expect(testimony.evidence_excerpt).to eq(verbatim_excerpt)
      expect(testimony.argument_markdown).to include("essential protections that strengthen tenant rights")
    end

    it "accepts payloads with symbol keys via indifferent access" do
      symbol_payload = {
        draft_news_testimonies: [
          {
            bill_news_article_id: eligible_op_ed.id,
            text_version_id: op_ed_text_version.id,
            author_name: "Jane Columnist",
            outlet_name: "The Baltimore Sun",
            canonical_url: "https://baltimoresun.com/opinion/council-bill-100-support",
            stance: "support",
            argument: "Symbol key argument.",
            evidence_excerpt: verbatim_excerpt
          }
        ]
      }

      expect {
        described_class.persist_drafts!(
          bill: bill,
          payload: symbol_payload,
          snapshot: snapshot,
          run_receipt: "receipt-sym"
        )
      }.to change(NewsArticleTestimony, :count).by(1)
    end

    it "registers NewsArticleSourceUse records on the snapshot with grounding_status: 'pending'" do
      expect {
        described_class.persist_drafts!(
          bill: bill,
          payload: valid_commentary_payload,
          snapshot: snapshot,
          run_receipt: "receipt-1"
        )
      }.to change(NewsArticleSourceUse, :count).by(1)

      source_use = snapshot.source_uses.last
      expect(source_use.bill_news_article_id).to eq(eligible_op_ed.id)
      expect(source_use.text_version_id).to eq(op_ed_text_version.id)
      expect(source_use.evidence_excerpt).to eq(verbatim_excerpt)
      expect(source_use.citation_url).to eq("https://baltimoresun.com/opinion/council-bill-100-support")
      expect(source_use.grounding_status).to eq("pending")
    end

    it "never creates Organization or OrganizationBillPosition records" do
      expect {
        described_class.persist_drafts!(
          bill: bill,
          payload: valid_commentary_payload,
          snapshot: snapshot,
          run_receipt: "receipt-1"
        )
      }.to change(Organization, :count).by(0).and change(OrganizationBillPosition, :count).by(0)
    end

    it "refuses to extract testimony if evidence excerpt is not genuinely present in article text" do
      invalid_payload = {
        "draft_news_testimonies" => [
          {
            "bill_news_article_id" => eligible_op_ed.id,
            "text_version_id" => op_ed_text_version.id,
            "author_name" => "Jane Columnist",
            "outlet_name" => "The Baltimore Sun",
            "canonical_url" => "https://baltimoresun.com/opinion/council-bill-100-support",
            "stance" => "support",
            "argument" => "Invented argument without excerpt in source text.",
            "evidence_excerpt" => "This sentence definitely does not exist in the article text anywhere."
          }
        ]
      }

      expect {
        described_class.persist_drafts!(
          bill: bill,
          payload: invalid_payload,
          snapshot: snapshot
        )
      }.not_to change(NewsArticleTestimony, :count)
    end

    it "refuses testimony where stance does not match the administrator classified stance" do
      mismatched_stance_payload = {
        "draft_news_testimonies" => [
          {
            "bill_news_article_id" => eligible_op_ed.id,
            "text_version_id" => op_ed_text_version.id,
            "author_name" => "Jane Columnist",
            "outlet_name" => "The Baltimore Sun",
            "canonical_url" => "https://baltimoresun.com/opinion/council-bill-100-support",
            "stance" => "oppose", # Eligible op-ed is admin-classified as "support"
            "argument" => "Arguments trying to oppose despite admin support stance.",
            "evidence_excerpt" => verbatim_excerpt
          }
        ]
      }

      expect {
        described_class.persist_drafts!(
          bill: bill,
          payload: mismatched_stance_payload,
          snapshot: snapshot
        )
      }.not_to change(NewsArticleTestimony, :count)
    end
  end

  describe "staleness detection on NewsArticleTestimony (#stale?)" do
    let(:verbatim_excerpt) { "Council Bill 100 provides essential housing protections" }
    let!(:testimony) do
      described_class.persist_drafts!(
        bill: bill,
        payload: {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "author_name" => "Jane Columnist",
              "outlet_name" => "The Baltimore Sun",
              "canonical_url" => "https://baltimoresun.com/opinion/council-bill-100-support",
              "stance" => "support",
              "argument" => "Essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        },
        snapshot: snapshot
      ).first
    end

    it "returns false when the article stance, stance_version, and text version are unchanged" do
      expect(testimony.stale?).to be false
    end

    it "returns true if the article stance changes" do
      eligible_op_ed.update_columns(stance: "oppose")
      expect(testimony.stale?).to be true
    end

    it "returns true if the article stance_version increments" do
      eligible_op_ed.set_stance!("support", by: admin)
      expect(testimony.stale?).to be true
    end

    it "returns true if the article text version changes" do
      new_tv = create(
        :news_article_text_version,
        :extracted,
        news_article: op_ed_article,
        text: "Updated text version #{verbatim_excerpt}"
      )
      eligible_op_ed.update!(current_text_version: new_tv)
      expect(testimony.stale?).to be true
    end

    it "returns true if the article approval is withdrawn" do
      eligible_op_ed.withdraw_approval!(by: admin)
      expect(testimony.stale?).to be true
    end
  end

  describe ".publish_commentary! (Gate generated news publication on validated evidence)" do
    let(:verbatim_excerpt) { "Council Bill 100 provides essential housing protections" }
    let!(:testimony) do
      described_class.persist_drafts!(
        bill: bill,
        payload: {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "author_name" => "Jane Columnist",
              "outlet_name" => "The Baltimore Sun",
              "canonical_url" => "https://baltimoresun.com/opinion/council-bill-100-support",
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        },
        snapshot: snapshot
      ).first
    end

    it "publishes draft commentary when grounding is supported and article version is fresh" do
      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        errors: []
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(supported_grounding)

      published = described_class.publish_commentary!(bill: bill, snapshot: snapshot)

      expect(published).to include(testimony)
      testimony.reload
      expect(testimony.publication_state).to eq("published")
      expect(testimony[:published_at]).to be_present
    end

    it "withdraws previous published commentary for the same bill_news_article when publishing new commentary" do
      prior_testimony = create(
        :news_article_testimony,
        bill_news_article: eligible_op_ed,
        news_article_text_version: op_ed_text_version,
        news_article_source_snapshot: snapshot,
        publication_state: "published",
        published_at: 1.day.ago,
        stance: "support",
        argument_markdown: "Prior commentary",
        evidence_excerpt: verbatim_excerpt,
        citation_url: "https://baltimoresun.com/opinion/council-bill-100-support",
        outlet_name: "The Baltimore Sun",
        text_digest: op_ed_text_version.digest
      )

      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        errors: []
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(supported_grounding)

      described_class.publish_commentary!(bill: bill, snapshot: snapshot)

      expect(prior_testimony.reload.publication_state).to eq("withdrawn")
      expect(testimony.reload.publication_state).to eq("published")
    end

    it "leaves commentary in draft state when grounding is unsupported" do
      unsupported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: false,
        unsupported?: true,
        indeterminate?: false,
        errors: ["Claim unsupported"]
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(unsupported_grounding)

      published = described_class.publish_commentary!(bill: bill, snapshot: snapshot)

      expect(published).to be_empty
      expect(testimony.reload.publication_state).to eq("draft")
      expect(testimony[:published_at]).to be_nil
    end

    it "leaves commentary in draft state when article version is stale (e.g. approval withdrawn)" do
      eligible_op_ed.withdraw_approval!(by: admin)

      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        errors: []
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(supported_grounding)

      published = described_class.publish_commentary!(bill: bill, snapshot: snapshot)

      expect(published).to be_empty
      expect(testimony.reload.publication_state).to eq("draft")
    end

    it "returns empty array and does not publish if snapshot belongs to a different bill" do
      other_bill = create(:bill)
      other_snapshot = NewsArticleSourceSnapshotService.capture!(
        bill: other_bill,
        purpose: "testimony",
        run_receipt: "receipt-other-bill",
        sources: []
      )

      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        errors: []
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(supported_grounding)

      published = described_class.publish_commentary!(bill: bill, snapshot: other_snapshot)

      expect(published).to be_empty
      expect(testimony.reload.publication_state).to eq("draft")
    end

    it "returns empty array and leaves drafts when snapshot eligibility comparison fails" do
      eligible_op_ed.update_columns(stance: "oppose", stance_version: 2)

      supported_grounding = instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        errors: []
      )
      allow(NewsClaimGroundingService).to receive(:call).and_return(supported_grounding)

      published = described_class.publish_commentary!(bill: bill, snapshot: snapshot)

      expect(published).to be_empty
      expect(testimony.reload.publication_state).to eq("draft")
    end

    it "passes content formatted with markdown citation link to NewsClaimGroundingService so prose check succeeds" do
      expect(NewsClaimGroundingService).to receive(:call) do |args|
        expect(args[:content]).to include(testimony.citation_url)
        expect(args[:content]).to include(testimony.argument_markdown)
        instance_double(
          NewsClaimGroundingService::Result,
          supported?: true,
          unsupported?: false,
          indeterminate?: false,
          errors: []
        )
      end

      published = described_class.publish_commentary!(bill: bill, snapshot: snapshot)

      expect(published).to include(testimony)
      expect(testimony.reload.publication_state).to eq("published")
    end
  end

  describe "commentary attribution integrity (Ground published opinion testimony in article evidence)" do
    let(:verbatim_excerpt) { "Council Bill 100 provides essential housing protections" }
    let(:supported_grounding) do
      instance_double(
        NewsClaimGroundingService::Result,
        supported?: true,
        unsupported?: false,
        indeterminate?: false,
        errors: []
      )
    end

    before do
      allow(NewsClaimGroundingService).to receive(:call).and_return(supported_grounding)
    end

    describe "reproduced defect: mismatched author_name and outlet_name in payload" do
      it "refuses to persist or publish fabricated author and publisher identities" do
        mismatched_payload = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "author_name" => "Invented Mayor",
              "outlet_name" => "Invented Publisher",
              "canonical_url" => op_ed_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections that will prevent arbitrary evictions across the city.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        drafts = described_class.persist_drafts!(
          bill: bill,
          payload: mismatched_payload,
          snapshot: snapshot
        )

        expect(drafts).to be_empty
        expect(NewsArticleTestimony.where(author_name: "Invented Mayor")).not_to exist
        expect(NewsArticleTestimony.where(outlet_name: "Invented Publisher")).not_to exist

        published = described_class.publish_commentary!(bill: bill, snapshot: snapshot)
        expect(published).to be_empty
      end
    end

    describe "control 1: matching generated metadata" do
      it "persists and publishes with authoritative identity" do
        matching_payload = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "author_name" => "Jane Columnist",
              "outlet_name" => "The Baltimore Sun",
              "canonical_url" => op_ed_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        drafts = described_class.persist_drafts!(bill: bill, payload: matching_payload, snapshot: snapshot)
        expect(drafts.size).to eq(1)
        draft = drafts.first
        expect(draft.author_name).to eq("Jane Columnist")
        expect(draft.outlet_name).to eq("The Baltimore Sun")

        published = described_class.publish_commentary!(bill: bill, snapshot: snapshot)
        expect(published).to include(draft)
        expect(draft.reload.publication_state).to eq("published")

        raw = NewsArticleTestimonyResource.new(draft).serializable_hash #: Hash[Symbol, untyped]
        serialized = raw.transform_keys(&:to_s)
        expect(serialized["author_name"]).to eq("Jane Columnist")
        expect(serialized["outlet_name"]).to eq("The Baltimore Sun")
      end
    end

    describe "control 2: omitted generated metadata" do
      it "uses authoritative article identity from NewsArticle" do
        omitted_payload = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "canonical_url" => op_ed_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        drafts = described_class.persist_drafts!(bill: bill, payload: omitted_payload, snapshot: snapshot)
        expect(drafts.size).to eq(1)
        draft = drafts.first
        expect(draft.author_name).to eq("Jane Columnist")
        expect(draft.outlet_name).to eq("The Baltimore Sun")

        published = described_class.publish_commentary!(bill: bill, snapshot: snapshot)
        expect(published).to include(draft)

        raw = NewsArticleTestimonyResource.new(draft.reload).serializable_hash #: Hash[Symbol, untyped]
        serialized = raw.transform_keys(&:to_s)
        expect(serialized["author_name"]).to eq("Jane Columnist")
        expect(serialized["outlet_name"]).to eq("The Baltimore Sun")
      end
    end

    describe "control 3: unknown author on NewsArticle" do
      it "refuses draft when payload attempts to invent an author" do
        anonymous_article = create(
          :news_article,
          :op_ed,
          title: "Community Housing Perspectives",
          author_name: nil,
          outlet_name: "The Baltimore Sun",
          canonical_url: "https://baltimoresun.com/opinion/community-housing"
        )
        anonymous_tv = create(
          :news_article_text_version,
          :extracted,
          news_article: anonymous_article,
          text: "Council Bill 100 provides essential housing protections for city residents."
        )
        eligible_anonymous_bna = create(
          :bill_news_article,
          :approved,
          :support,
          bill: bill,
          news_article: anonymous_article,
          current_text_version: anonymous_tv
        )
        anonymous_snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "testimony",
          run_receipt: "receipt-anon-1",
          sources: [eligible_anonymous_bna]
        )

        payload_with_invented_author = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_anonymous_bna.id,
              "text_version_id" => anonymous_tv.id,
              "author_name" => "Invented Freelancer",
              "outlet_name" => "The Baltimore Sun",
              "canonical_url" => anonymous_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        drafts = described_class.persist_drafts!(
          bill: bill,
          payload: payload_with_invented_author,
          snapshot: anonymous_snapshot
        )

        expect(drafts).to be_empty
        expect(NewsArticleTestimony.where(author_name: "Invented Freelancer")).not_to exist
      end

      it "preserves author as nil while retaining outlet_name when payload omits author" do
        anonymous_article = create(
          :news_article,
          :op_ed,
          title: "Community Housing Perspectives",
          author_name: nil,
          outlet_name: "The Baltimore Sun",
          canonical_url: "https://baltimoresun.com/opinion/community-housing"
        )
        anonymous_tv = create(
          :news_article_text_version,
          :extracted,
          news_article: anonymous_article,
          text: "Council Bill 100 provides essential housing protections for city residents."
        )
        eligible_anonymous_bna = create(
          :bill_news_article,
          :approved,
          :support,
          bill: bill,
          news_article: anonymous_article,
          current_text_version: anonymous_tv
        )
        anonymous_snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "testimony",
          run_receipt: "receipt-anon-2",
          sources: [eligible_anonymous_bna]
        )

        payload_omitted_author = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_anonymous_bna.id,
              "text_version_id" => anonymous_tv.id,
              "outlet_name" => "The Baltimore Sun",
              "canonical_url" => anonymous_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        drafts = described_class.persist_drafts!(
          bill: bill,
          payload: payload_omitted_author,
          snapshot: anonymous_snapshot
        )

        expect(drafts.size).to eq(1)
        draft = drafts.first
        expect(draft.author_name).to be_nil
        expect(draft.outlet_name).to eq("The Baltimore Sun")

        raw = NewsArticleTestimonyResource.new(draft).serializable_hash #: Hash[Symbol, untyped]
        serialized = raw.transform_keys(&:to_s)
        expect(serialized["author_name"]).to be_nil
        expect(serialized["outlet_name"]).to eq("The Baltimore Sun")
      end
    end

    describe "control 4: established editorial-board identity" do
      it "refuses draft when payload attempts to attribute editorial to individual person" do
        editorial_article = create(
          :news_article,
          :editorial,
          title: "The Sun Endorses Council Bill 100",
          author_name: nil,
          outlet_name: "The Baltimore Sun",
          canonical_url: "https://baltimoresun.com/opinion/editorial-bill-100"
        )
        editorial_tv = create(
          :news_article_text_version,
          :extracted,
          news_article: editorial_article,
          text: "Council Bill 100 provides essential housing protections that Baltimore needs."
        )
        eligible_editorial_bna = create(
          :bill_news_article,
          :approved,
          :support,
          bill: bill,
          news_article: editorial_article,
          current_text_version: editorial_tv
        )
        editorial_snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "testimony",
          run_receipt: "receipt-ed-1",
          sources: [eligible_editorial_bna]
        )

        payload_with_fabricated_editor = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_editorial_bna.id,
              "text_version_id" => editorial_tv.id,
              "author_name" => "Individual Editor",
              "outlet_name" => "The Baltimore Sun",
              "canonical_url" => editorial_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        drafts = described_class.persist_drafts!(
          bill: bill,
          payload: payload_with_fabricated_editor,
          snapshot: editorial_snapshot
        )

        expect(drafts).to be_empty
        expect(NewsArticleTestimony.where(author_name: "Individual Editor")).not_to exist
      end

      it "accepts editorial when payload specifies Editorial Board and preserves institutional attribution" do
        editorial_article = create(
          :news_article,
          :editorial,
          title: "The Sun Endorses Council Bill 100",
          author_name: nil,
          outlet_name: "The Baltimore Sun",
          canonical_url: "https://baltimoresun.com/opinion/editorial-bill-100"
        )
        editorial_tv = create(
          :news_article_text_version,
          :extracted,
          news_article: editorial_article,
          text: "Council Bill 100 provides essential housing protections that Baltimore needs."
        )
        eligible_editorial_bna = create(
          :bill_news_article,
          :approved,
          :support,
          bill: bill,
          news_article: editorial_article,
          current_text_version: editorial_tv
        )
        editorial_snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "testimony",
          run_receipt: "receipt-ed-2",
          sources: [eligible_editorial_bna]
        )

        payload_with_board = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_editorial_bna.id,
              "text_version_id" => editorial_tv.id,
              "author_name" => "Editorial Board",
              "outlet_name" => "The Baltimore Sun",
              "canonical_url" => editorial_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        drafts = described_class.persist_drafts!(
          bill: bill,
          payload: payload_with_board,
          snapshot: editorial_snapshot
        )

        expect(drafts.size).to eq(1)
        draft = drafts.first
        expect(draft.author_name).to be_nil
        expect(draft.outlet_name).to eq("The Baltimore Sun")

        raw = NewsArticleTestimonyResource.new(draft).serializable_hash #: Hash[Symbol, untyped]
        serialized = raw.transform_keys(&:to_s)
        expect(serialized["author_name"]).to be_nil
        expect(serialized["outlet_name"]).to eq("The Baltimore Sun")
      end
    end

    describe "control 5: preserving distinction between publisher and speaker/author" do
      it "retains author as the speaker and outlet as the publisher without conflation" do
        valid_payload = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "author_name" => "Jane Columnist",
              "outlet_name" => "The Baltimore Sun",
              "canonical_url" => op_ed_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        drafts = described_class.persist_drafts!(bill: bill, payload: valid_payload, snapshot: snapshot)
        draft = drafts.first

        expect(draft.author_name).to eq("Jane Columnist")
        expect(draft.outlet_name).to eq("The Baltimore Sun")
        expect(draft.author_name).not_to eq(draft.outlet_name)

        raw = NewsArticleTestimonyResource.new(draft).serializable_hash #: Hash[Symbol, untyped]
        serialized = raw.transform_keys(&:to_s)
        expect(serialized["author_name"]).to eq("Jane Columnist")
        expect(serialized["outlet_name"]).to eq("The Baltimore Sun")
      end
    end

    describe "control 6: preserving previous valid public commentary when replacement fails" do
      it "keeps existing published commentary when replacement payload has mismatched attribution and is refused" do
        existing_published_testimony = create(
          :news_article_testimony,
          bill_news_article: eligible_op_ed,
          news_article_text_version: op_ed_text_version,
          news_article_source_snapshot: snapshot,
          publication_state: "published",
          published_at: 2.days.ago,
          stance: "support",
          argument_markdown: "Original valid published commentary that should not be lost.",
          evidence_excerpt: verbatim_excerpt,
          citation_url: op_ed_article.canonical_url,
          outlet_name: "The Baltimore Sun",
          author_name: "Jane Columnist",
          text_digest: op_ed_text_version.digest
        )

        new_snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "testimony",
          run_receipt: "receipt-replacement-1",
          sources: [eligible_op_ed]
        )

        mismatched_replacement_payload = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "author_name" => "Invented Mayor",
              "outlet_name" => "Invented Publisher",
              "canonical_url" => op_ed_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        drafts = described_class.persist_drafts!(
          bill: bill,
          payload: mismatched_replacement_payload,
          snapshot: new_snapshot
        )

        expect(drafts).to be_empty
        published = described_class.publish_commentary!(bill: bill, snapshot: new_snapshot)
        expect(published).to be_empty
        expect(existing_published_testimony.reload.publication_state).to eq("published")
      end

      it "keeps existing published commentary when replacement draft fails grounding" do
        existing_published_testimony = create(
          :news_article_testimony,
          bill_news_article: eligible_op_ed,
          news_article_text_version: op_ed_text_version,
          news_article_source_snapshot: snapshot,
          publication_state: "published",
          published_at: 2.days.ago,
          stance: "support",
          argument_markdown: "Original valid published commentary that should not be lost.",
          evidence_excerpt: verbatim_excerpt,
          citation_url: op_ed_article.canonical_url,
          outlet_name: "The Baltimore Sun",
          author_name: "Jane Columnist",
          text_digest: op_ed_text_version.digest
        )

        new_snapshot = NewsArticleSourceSnapshotService.capture!(
          bill: bill,
          purpose: "testimony",
          run_receipt: "receipt-replacement-2",
          sources: [eligible_op_ed]
        )

        replacement_payload = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "canonical_url" => op_ed_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        drafts = described_class.persist_drafts!(
          bill: bill,
          payload: replacement_payload,
          snapshot: new_snapshot
        )
        expect(drafts.size).to eq(1)

        unsupported_grounding = instance_double(
          NewsClaimGroundingService::Result,
          supported?: false,
          unsupported?: true,
          indeterminate?: false,
          errors: ["Grounding failed"]
        )
        allow(NewsClaimGroundingService).to receive(:call).and_return(unsupported_grounding)

        published = described_class.publish_commentary!(bill: bill, snapshot: new_snapshot)
        expect(published).to be_empty
        expect(existing_published_testimony.reload.publication_state).to eq("published")
        expect(drafts.first.reload.publication_state).to eq("draft")
      end

      it "enforces case-sensitive author_name and outlet_name matching, refuses op_ed Editorial Board spoofing, and fails closed on non-string attribution values" do
        case_mismatch_payload = {
          "draft_news_testimonies" => [
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "author_name" => "jane columnist",
              "outlet_name" => "The Baltimore Sun",
              "canonical_url" => op_ed_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            },
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "author_name" => "Jane Columnist",
              "outlet_name" => "the baltimore sun",
              "canonical_url" => op_ed_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            },
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "author_name" => "Editorial Board",
              "outlet_name" => "The Baltimore Sun",
              "canonical_url" => op_ed_article.canonical_url,
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            },
            {
              "bill_news_article_id" => eligible_op_ed.id,
              "text_version_id" => op_ed_text_version.id,
              "author_name" => 12_345,
              "outlet_name" => ["The Baltimore Sun"],
              "canonical_url" => {"url" => op_ed_article.canonical_url},
              "stance" => "support",
              "argument" => "Council Bill 100 provides essential housing protections.",
              "evidence_excerpt" => verbatim_excerpt
            }
          ]
        }

        expect(described_class.persist_drafts!(bill: bill, payload: case_mismatch_payload, snapshot: snapshot)).to be_empty
      end

      it "rejects NewsArticleTestimony whose bill_news_article belongs to a different bill than news_article_source_snapshot" do
        other_bill = create(:bill, sway_locale: sway_locale)
        other_bna = create(:bill_news_article, :approved, :support, bill: other_bill, news_article: op_ed_article, current_text_version: op_ed_text_version)

        invalid_testimony = build(
          :news_article_testimony,
          bill_news_article: other_bna,
          news_article_text_version: op_ed_text_version,
          news_article_source_snapshot: snapshot
        )

        expect(invalid_testimony).not_to be_valid
        expect(invalid_testimony.errors[:bill_news_article]).to include("must belong to the snapshot's bill")
      end

      it "promotes the latest competing draft and withdraws earlier drafts in the same snapshot, rolling back atomically on promotion error" do
        draft_1 = create(
          :news_article_testimony,
          bill_news_article: eligible_op_ed,
          news_article_text_version: op_ed_text_version,
          news_article_source_snapshot: snapshot,
          publication_state: "draft",
          stance: "support",
          stance_version: eligible_op_ed.stance_version,
          review_version: eligible_op_ed.review_version,
          argument_markdown: "First competing draft.",
          evidence_excerpt: verbatim_excerpt,
          citation_url: op_ed_article.canonical_url,
          outlet_name: "The Baltimore Sun",
          author_name: "Jane Columnist",
          text_digest: op_ed_text_version.digest
        )
        draft_2 = create(
          :news_article_testimony,
          bill_news_article: eligible_op_ed,
          news_article_text_version: op_ed_text_version,
          news_article_source_snapshot: snapshot,
          publication_state: "draft",
          stance: "support",
          stance_version: eligible_op_ed.stance_version,
          review_version: eligible_op_ed.review_version,
          argument_markdown: "Second competing draft.",
          evidence_excerpt: verbatim_excerpt,
          citation_url: op_ed_article.canonical_url,
          outlet_name: "The Baltimore Sun",
          author_name: "Jane Columnist",
          text_digest: op_ed_text_version.digest
        )

        published = described_class.publish_commentary!(bill: bill, snapshot: snapshot)
        expect(published).to include(draft_2)
        expect(draft_2.reload.publication_state).to eq("published")
        expect(draft_1.reload.publication_state).to eq("withdrawn")
        expect(bill.reload.news_testimonies).to contain_exactly(draft_2)

        indeterminate_grounding = instance_double(
          NewsClaimGroundingService::Result,
          supported?: false,
          unsupported?: false,
          indeterminate?: true,
          errors: ["LLM timeout"]
        )
        allow(NewsClaimGroundingService).to receive(:call).and_return(indeterminate_grounding)

        snap_indet = NewsArticleSourceSnapshotService.capture!(bill: bill, purpose: "testimony", run_receipt: "indet-run", sources: [eligible_op_ed])
        draft_indet = create(
          :news_article_testimony,
          bill_news_article: eligible_op_ed,
          news_article_text_version: op_ed_text_version,
          news_article_source_snapshot: snap_indet,
          publication_state: "draft",
          stance: "support",
          stance_version: eligible_op_ed.stance_version,
          review_version: eligible_op_ed.review_version,
          argument_markdown: "Indeterminate draft.",
          evidence_excerpt: verbatim_excerpt,
          citation_url: op_ed_article.canonical_url,
          outlet_name: "The Baltimore Sun",
          author_name: "Jane Columnist",
          text_digest: op_ed_text_version.digest
        )
        expect(described_class.publish_commentary!(bill: bill, snapshot: snap_indet)).to be_empty
        expect(draft_indet.reload.publication_state).to eq("draft")
        expect(draft_2.reload.publication_state).to eq("published")

        allow(NewsClaimGroundingService).to receive(:call).and_return(supported_grounding)
        snap_err = NewsArticleSourceSnapshotService.capture!(bill: bill, purpose: "testimony", run_receipt: "err-run", sources: [eligible_op_ed])
        draft_err = create(
          :news_article_testimony,
          bill_news_article: eligible_op_ed,
          news_article_text_version: op_ed_text_version,
          news_article_source_snapshot: snap_err,
          publication_state: "draft",
          stance: "support",
          stance_version: eligible_op_ed.stance_version,
          review_version: eligible_op_ed.review_version,
          argument_markdown: "Rollback draft.",
          evidence_excerpt: verbatim_excerpt,
          citation_url: op_ed_article.canonical_url,
          outlet_name: "The Baltimore Sun",
          author_name: "Jane Columnist",
          text_digest: op_ed_text_version.digest
        )
        allow_any_instance_of(NewsArticleTestimony).to receive(:update!).and_wrap_original do |method, *args| # rubocop:disable RSpec/AnyInstance
          if args.first.is_a?(Hash) && args.first[:publication_state] == "published" && method.receiver.id == draft_err.id
            raise ActiveRecord::RecordInvalid.new(draft_err)
          end
          method.call(*args)
        end

        expect {
          described_class.publish_commentary!(bill: bill, snapshot: snap_err)
        }.to raise_error(ActiveRecord::RecordInvalid)
        expect(draft_2.reload.publication_state).to eq("published")
        expect(draft_err.reload.publication_state).to eq("draft")
      end

      it "evaluates stale?(reload:) and currently_eligible?(reload:) across unpersisted and out-of-band mutations and refuses in-flight article_kind downgrade" do
        testimony = create(
          :news_article_testimony,
          bill_news_article: eligible_op_ed,
          news_article_text_version: op_ed_text_version,
          news_article_source_snapshot: snapshot,
          publication_state: "draft",
          stance: "support",
          stance_version: eligible_op_ed.stance_version,
          review_version: eligible_op_ed.review_version,
          argument_markdown: "Council Bill 100 provides essential housing protections.",
          evidence_excerpt: verbatim_excerpt,
          citation_url: op_ed_article.canonical_url,
          outlet_name: "The Baltimore Sun",
          author_name: "Jane Columnist",
          text_digest: op_ed_text_version.digest
        )

        expect(testimony.stale?(reload: false)).to be(false)
        expect(testimony.currently_eligible?(reload: false)).to be(true)

        testimony.bill_news_article.stance = "oppose"
        expect(testimony.stale?(reload: false)).to be(true)
        expect(testimony.currently_eligible?(reload: false)).to be(false)
        expect(testimony.stale?(reload: true)).to be(false)
        expect(testimony.currently_eligible?(reload: true)).to be(true)

        BillNewsArticle.where(id: eligible_op_ed.id).update_all(stance_version: eligible_op_ed.stance_version + 1)
        expect(testimony.stale?(reload: false)).to be(false)
        expect(testimony.stale?(reload: true)).to be(true)

        BillNewsArticle.where(id: eligible_op_ed.id).update_all(stance_version: testimony.stance_version)
        NewsArticle.where(id: op_ed_article.id).update_all(article_kind: "reporting")

        expect(described_class.publish_commentary!(bill: bill, snapshot: snapshot)).to be_empty
        expect(testimony.reload.publication_state).to eq("draft")
      end
    end
  end
end
