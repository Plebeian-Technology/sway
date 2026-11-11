# frozen_string_literal: true

require "rails_helper"

RSpec.describe ReviewBillNewsArticleService, type: :service do
  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }
  let(:other_bill) { create(:bill, sway_locale: sway_locale) }
  let(:admin) { create(:user, :sway_admin) }
  let(:regular_user) { create(:user) }
  let(:news_article) { create(:news_article) }
  let(:bill_news_article) { create(:bill_news_article, bill: bill, news_article: news_article) }

  describe ".call" do
    it "raises ArgumentError when admin is not a Sway admin" do
      expect {
        described_class.call(
          bill: bill,
          bill_news_article: bill_news_article,
          admin: regular_user,
          params: {approved: true}
        )
      }.to raise_error(ArgumentError, /admin must be a Sway admin/)
    end

    it "raises ArgumentError when bill_news_article does not belong to bill" do
      other_bna = create(:bill_news_article, bill: other_bill, news_article: news_article)

      expect {
        described_class.call(
          bill: bill,
          bill_news_article: other_bna,
          admin: admin,
          params: {approved: true}
        )
      }.to raise_error(ArgumentError, /does not belong to the specified bill/)
    end

    it "approves an unapproved article and increments review_version" do
      result = described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {approved: true}
      )

      expect(result.approved).to be(true)
      expect(result.approved_by).to eq(admin)
      expect(result.approved_at).to be_present
      expect(result.review_version).to eq(1)
    end

    it "withdraws approval and increments review_version" do
      bill_news_article.approve!(by: admin)

      result = described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {approved: false}
      )

      expect(result.approved).to be(false)
      expect(result.review_version).to eq(2)
    end

    it "does not increment review_version if approval state is unchanged" do
      expect(bill_news_article.approved).to be(false)
      expect(bill_news_article.review_version).to eq(0)

      result = described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {approved: false}
      )

      expect(result.approved).to be(false)
      expect(result.review_version).to eq(0)
    end

    it "sets opinion stance and increments stance_version" do
      result = described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {stance: "support"}
      )

      expect(result.stance).to eq("support")
      expect(result.stance_by).to eq(admin)
      expect(result.stance_version).to eq(1)
    end

    it "clears stance and increments stance_version" do
      bill_news_article.set_stance!("support", by: admin)

      result = described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {stance: nil}
      )

      expect(result.stance).to be_nil
      expect(result.stance_by).to eq(admin)
      expect(result.stance_version).to eq(2)
    end

    it "does not increment stance_version if stance is unchanged" do
      bill_news_article.set_stance!("support", by: admin)
      expect(bill_news_article.stance_version).to eq(1)

      result = described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {stance: "support"}
      )

      expect(result.stance).to eq("support")
      expect(result.stance_version).to eq(1)
    end

    it "raises ArgumentError on invalid stance" do
      expect {
        described_class.call(
          bill: bill,
          bill_news_article: bill_news_article,
          admin: admin,
          params: {stance: "neutral"}
        )
      }.to raise_error(ArgumentError, /Invalid stance/)
    end

    it "updates article_kind on news_article" do
      expect(news_article.article_kind).to eq("reporting")

      described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {article_kind: "op_ed"}
      )

      expect(news_article.reload.article_kind).to eq("op_ed")
    end

    it "creates a manual NewsArticleTextVersion and increments review_version" do
      expect {
        described_class.call(
          bill: bill,
          bill_news_article: bill_news_article,
          admin: admin,
          params: {text: "Verified reporting text."}
        )
      }.to change(NewsArticleTextVersion, :count).by(1)

      text_version = bill_news_article.reload.current_text_version
      expect(text_version.origin).to eq("manual")
      expect(text_version.actor).to eq(admin)
      expect(text_version.text).to eq("Verified reporting text.")
      expect(text_version.extraction_status).to eq("extracted")
      expect(text_version.digest).to eq(Digest::SHA256.hexdigest("Verified reporting text."))
      expect(bill_news_article.review_version).to eq(1)
    end

    it "enables synthesis eligibility when manual text is added to an approved article" do
      bill_news_article.approve!(by: admin)
      expect(bill_news_article.eligible_for_link?).to be(true)
      expect(bill_news_article.eligible_for_synthesis?).to be(false)

      described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {text: "Article body text here."}
      )

      reloaded = bill_news_article.reload
      expect(reloaded.eligible_for_link?).to be(true)
      expect(reloaded.eligible_for_synthesis?).to be(true)
    end
  end

  describe "evidence retraction for news draft organization positions" do
    it "marks news draft positions with evidence_retracted_at when an approved article is unapproved" do
      tv = create(
        :news_article_text_version,
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: "Original scraped text."
      )
      bill_news_article.update!(current_text_version: tv)
      bill_news_article.approve!(by: admin)

      news_draft = {
        "org_name" => "Civic Alliance",
        "stance" => "support",
        "summary" => "Quoted supporting the measure",
        "bill_news_article_id" => bill_news_article.id,
        "text_version_id" => tv.id,
        "evidence_excerpt" => "We fully support this legislation."
      }
      provisioning = create(:bill_llm_provisioning, bill: bill, draft_org_positions: [news_draft])

      described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {approved: false}
      )

      drafts = provisioning.reload.draft_org_positions
      expect(drafts.first["evidence_retracted_at"]).to be_present
      expect(Time.iso8601(drafts.first["evidence_retracted_at"])).to be_within(5.seconds).of(Time.current)
    end

    it "does not touch hearing testimony drafts or drafts from other news articles when unapproving" do
      tv = create(
        :news_article_text_version,
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: "Original scraped text."
      )
      other_art = create(:news_article)
      other_bna = create(:bill_news_article, bill: bill, news_article: other_art)
      other_tv = create(
        :news_article_text_version,
        news_article: other_art,
        origin: "retrieved",
        extraction_status: "extracted",
        text: "Other article text."
      )
      bill_news_article.update!(current_text_version: tv)
      bill_news_article.approve!(by: admin)
      other_bna.update!(current_text_version: other_tv)

      news_draft = {
        "org_name" => "Civic Alliance",
        "stance" => "support",
        "summary" => "Quoted supporting the measure",
        "bill_news_article_id" => bill_news_article.id,
        "text_version_id" => tv.id,
        "evidence_excerpt" => "We fully support this legislation."
      }
      hearing_draft = {
        "org_name" => "Hearing Organization",
        "stance" => "oppose",
        "summary" => "Testified against the bill at committee hearing."
      }
      other_news_draft = {
        "org_name" => "Other News Org",
        "stance" => "neutral",
        "summary" => "Quoted in unrelated article",
        "bill_news_article_id" => other_bna.id,
        "text_version_id" => other_tv.id,
        "evidence_excerpt" => "Statement in different outlet."
      }
      provisioning = create(
        :bill_llm_provisioning,
        bill: bill,
        draft_org_positions: [news_draft, hearing_draft, other_news_draft]
      )

      described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {approved: false}
      )

      drafts = provisioning.reload.draft_org_positions
      expect(drafts[0]["evidence_retracted_at"]).to be_present
      expect(drafts[1]["evidence_retracted_at"]).to be_nil
      expect(drafts[1]).to eq(hearing_draft)
      expect(drafts[2]["evidence_retracted_at"]).to be_nil
      expect(drafts[2]).to eq(other_news_draft)
    end

    it "marks drafts referencing older text versions with evidence_retracted_at when adding a new text version on an approved article" do
      tv = create(
        :news_article_text_version,
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: "Original scraped text."
      )
      bill_news_article.update!(current_text_version: tv)
      bill_news_article.approve!(by: admin)

      news_draft = {
        "org_name" => "Civic Alliance",
        "stance" => "support",
        "summary" => "Quoted supporting the measure",
        "bill_news_article_id" => bill_news_article.id,
        "text_version_id" => tv.id,
        "evidence_excerpt" => "We fully support this legislation."
      }
      provisioning = create(:bill_llm_provisioning, bill: bill, draft_org_positions: [news_draft])

      described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {text: "Updated manual text body."}
      )

      drafts = provisioning.reload.draft_org_positions
      expect(drafts.first["evidence_retracted_at"]).to be_present
      expect(bill_news_article.reload.current_text_version.origin).to eq("manual")
      expect(bill_news_article.current_text_version.id).not_to eq(tv.id)
    end

    it "preserves existing retraction timestamps when changing text on an unapproved article" do
      tv = create(
        :news_article_text_version,
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: "Original scraped text."
      )
      bill_news_article.update!(current_text_version: tv, approved: false)

      original_timestamp = 2.days.ago.utc.iso8601
      retracted_news_draft = {
        "org_name" => "Civic Alliance",
        "stance" => "support",
        "summary" => "Quoted supporting the measure",
        "bill_news_article_id" => bill_news_article.id,
        "text_version_id" => tv.id,
        "evidence_excerpt" => "We fully support this legislation.",
        "evidence_retracted_at" => original_timestamp
      }
      provisioning = create(:bill_llm_provisioning, bill: bill, draft_org_positions: [retracted_news_draft])

      described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {text: "Revised manual text for unapproved article."}
      )

      drafts = provisioning.reload.draft_org_positions
      expect(drafts.first["evidence_retracted_at"]).to eq(original_timestamp)
    end

    it "safely completes without error when bill has no bill_llm_provisioning or draft_org_positions is empty" do
      bill_news_article.approve!(by: admin)
      expect(bill.bill_llm_provisioning).to be_nil

      result_nil_prov = described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {approved: false}
      )
      expect(result_nil_prov.ok?).to be(true)

      bill_news_article.approve!(by: admin)
      provisioning = create(:bill_llm_provisioning, bill: bill, draft_org_positions: [])

      result_empty = described_class.call(
        bill: bill,
        bill_news_article: bill_news_article,
        admin: admin,
        params: {approved: false}
      )
      expect(result_empty.ok?).to be(true)
      expect(provisioning.reload.draft_org_positions).to eq([])
    end

    it "creates zero Organization and OrganizationBillPosition entities" do
      tv = create(
        :news_article_text_version,
        news_article: news_article,
        origin: "retrieved",
        extraction_status: "extracted",
        text: "Original scraped text."
      )
      bill_news_article.update!(current_text_version: tv)
      bill_news_article.approve!(by: admin)

      news_draft = {
        "org_name" => "Civic Alliance",
        "stance" => "support",
        "summary" => "Quoted supporting the measure",
        "bill_news_article_id" => bill_news_article.id,
        "text_version_id" => tv.id,
        "evidence_excerpt" => "We fully support this legislation."
      }
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [news_draft])

      expect {
        described_class.call(
          bill: bill,
          bill_news_article: bill_news_article,
          admin: admin,
          params: {approved: false}
        )
      }.to change(Organization, :count).by(0).and change(OrganizationBillPosition, :count).by(0)
    end
  end
end
