# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Batch summarisation#One reader decides whether a bill earns a batch item]]
RSpec.describe SummaryItemEligibility do
  def eligibility_for(bill, provisioning)
    described_class.for(bill: bill, provisioning: provisioning)
  end

  describe "an operator's paste owns the row" do
    let(:bill) { create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.") }
    let(:provisioning) do
      create(:bill_llm_provisioning, :with_testimony, bill: bill,
        summary_run_id: SummaryRunMarker.operator_paste)
    end

    it "reports operator_paste?" do
      expect(eligibility_for(bill, provisioning).operator_paste?).to be(true)
    end

    it "still reports the summary evidence it can see" do
      expect(eligibility_for(bill, provisioning).summary?).to be(true)
    end

    it "still reports the positions evidence it can see" do
      expect(eligibility_for(bill, provisioning).positions?).to be(true)
    end
  end

  describe "no source text" do
    let(:bill) { create(:bill, extracted_text: nil) }
    let(:provisioning) { create(:bill_llm_provisioning, :with_testimony, bill: bill) }

    it "does not report an operator paste" do
      expect(eligibility_for(bill, provisioning).operator_paste?).to be(false)
    end

    it "earns no summary item" do
      expect(eligibility_for(bill, provisioning).summary?).to be(false)
    end

    it "still earns a positions item, since testimony is present" do
      expect(eligibility_for(bill, provisioning).positions?).to be(true)
    end
  end

  describe "no testimony" do
    let(:bill) { create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.") }
    let(:provisioning) { create(:bill_llm_provisioning, bill: bill) }

    it "earns no positions item" do
      expect(eligibility_for(bill, provisioning).positions?).to be(false)
    end

    it "still earns a summary item, since source text is present" do
      expect(eligibility_for(bill, provisioning).summary?).to be(true)
    end
  end

  describe "the ordinary case" do
    let(:bill) { create(:bill, extracted_text: "Section 1. The Mayor shall submit an annual report.") }
    let(:provisioning) { create(:bill_llm_provisioning, :with_testimony, bill: bill) }

    it "earns a summary item" do
      expect(eligibility_for(bill, provisioning).summary?).to be(true)
    end

    it "earns a positions item" do
      expect(eligibility_for(bill, provisioning).positions?).to be(true)
    end
  end

  describe "neither source text nor testimony" do
    let(:bill) { create(:bill, extracted_text: nil) }
    let(:provisioning) { create(:bill_llm_provisioning, bill: bill) }

    it "earns no summary item" do
      expect(eligibility_for(bill, provisioning).summary?).to be(false)
    end

    it "earns no positions item" do
      expect(eligibility_for(bill, provisioning).positions?).to be(false)
    end
  end

  describe "published opinion commentary eligibility" do
    let(:bill) { create(:bill, extracted_text: nil) }
    let(:provisioning) { create(:bill_llm_provisioning, bill: bill) }

    it "earns a positions item when an approved text-bearing op-ed with stance exists, without marking hearing testimony present" do
      article = create(:news_article, :op_ed)
      tv = create(:news_article_text_version, :extracted, news_article: article, text: "Op-ed text supporting housing reform.")
      create(:bill_news_article, :approved, :support, bill: bill, news_article: article, current_text_version: tv)

      eligibility = eligibility_for(bill, provisioning)
      expect(eligibility.commentary_eligible?).to be(true)
      expect(eligibility.positions?).to be(true)
      expect(provisioning.testimony_present?).to be(false)
      expect(eligibility.hearing_testimony?).to be(false)
    end

    it "earns no positions item when the op-ed has no extracted text" do
      article = create(:news_article, :op_ed)
      create(:bill_news_article, :approved, :support, bill: bill, news_article: article, current_text_version: nil)

      eligibility = eligibility_for(bill, provisioning)
      expect(eligibility.commentary_eligible?).to be(false)
      expect(eligibility.positions?).to be(false)
    end

    it "earns a positions item when the article is reporting, but commentary_eligible? remains false" do
      article = create(:news_article, article_kind: "reporting")
      tv = create(:news_article_text_version, :extracted, news_article: article, text: "Factual news report.")
      create(:bill_news_article, :approved, :support, bill: bill, news_article: article, current_text_version: tv)

      eligibility = eligibility_for(bill, provisioning)
      expect(eligibility.commentary_eligible?).to be(false)
      expect(eligibility.positions?).to be(true)
    end
  end

  describe "news reporting eligibility" do
    let(:bill) { create(:bill, extracted_text: nil) }
    let(:provisioning) { create(:bill_llm_provisioning, bill: bill) }

    it "earns a positions item when an approved text-bearing reporting article exists, while commentary_eligible? remains false" do
      article = create(:news_article, article_kind: "reporting")
      tv = create(:news_article_text_version, :extracted, news_article: article, text: "Factual news report.")
      create(:bill_news_article, :approved, bill: bill, news_article: article, current_text_version: tv)

      eligibility = eligibility_for(bill, provisioning)
      expect(eligibility.commentary_eligible?).to be(false)
      expect(eligibility.news_reporting_eligible?).to be(true)
      expect(eligibility.positions?).to be(true)
      expect(provisioning.testimony_present?).to be(false)
      expect(eligibility.hearing_testimony?).to be(false)
    end

    it "earns no positions item when the reporting article is not approved" do
      article = create(:news_article, article_kind: "reporting")
      tv = create(:news_article_text_version, :extracted, news_article: article, text: "Factual news report.")
      create(:bill_news_article, approved: false, bill: bill, news_article: article, current_text_version: tv)

      eligibility = eligibility_for(bill, provisioning)
      expect(eligibility.news_reporting_eligible?).to be(false)
      expect(eligibility.positions?).to be(false)
    end

    it "earns no positions item when the reporting article has no extracted text" do
      article = create(:news_article, article_kind: "reporting")
      create(:bill_news_article, :approved, bill: bill, news_article: article, current_text_version: nil)

      eligibility = eligibility_for(bill, provisioning)
      expect(eligibility.news_reporting_eligible?).to be(false)
      expect(eligibility.positions?).to be(false)
    end

    it "earns no positions item when the reporting article text version is paywalled" do
      article = create(:news_article, article_kind: "reporting")
      tv = create(:news_article_text_version, :paywalled, news_article: article)
      create(:bill_news_article, :approved, bill: bill, news_article: article, current_text_version: tv)

      eligibility = eligibility_for(bill, provisioning)
      expect(eligibility.news_reporting_eligible?).to be(false)
      expect(eligibility.positions?).to be(false)
    end

    it "earns no positions item when the reporting article extraction failed" do
      article = create(:news_article, article_kind: "reporting")
      tv = create(:news_article_text_version, :failed, news_article: article)
      create(:bill_news_article, :approved, bill: bill, news_article: article, current_text_version: tv)

      eligibility = eligibility_for(bill, provisioning)
      expect(eligibility.news_reporting_eligible?).to be(false)
      expect(eligibility.positions?).to be(false)
    end
  end
end
