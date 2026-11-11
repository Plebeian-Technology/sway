# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/llm-summaries#Batch summarisation#What a custom_id has to carry]]
RSpec.describe SummaryBatchItem do
  let(:sway_locale) { SwayLocale.find_by(city: "baltimore") || create(:sway_locale, :baltimore) }
  let(:bill) do
    create(:bill, external_id: "SBI-1", sway_locale: sway_locale,
      extracted_text: "Section 1. The Mayor shall report annually.",
      scheduled_release_date_utc: 700.days.ago)
  end

  describe ".custom_id" do
    it "names the bill and the answer type, so a result read hours later resolves to both" do
      expect(described_class.custom_id(bill_id: 42, answer_type: described_class::SUMMARY))
        .to eq("bill__42__summary")
    end

    it "builds an id the batch API accepts" do
      expect(Llm::BatchCustomId.valid?(
        described_class.custom_id(bill_id: 42, answer_type: described_class::POSITIONS)
      )).to be(true)
    end

    it "rebuilds the same id the submission wrote, which is what makes the read-back map work" do
      submitted = described_class.build(
        bill: bill, answer_type: described_class::SUMMARY, model: "claude-sonnet-5-5", active_categories: []
      )

      expect(described_class.custom_id(bill_id: bill.id, answer_type: described_class::SUMMARY))
        .to eq(submitted.custom_id)
    end
  end

  describe ".validation_schema" do
    it "answers the summary schema for the summary answer type" do
      expect(described_class.validation_schema(described_class::SUMMARY)).to eq(BILL_SUMMARY_SCHEMA)
    end

    it "answers the positions schema for the positions answer type" do
      expect(described_class.validation_schema(described_class::POSITIONS)).to eq(BILL_POSITIONS_SCHEMA)
    end

    it "refuses an answer type it has no schema for" do
      expect { described_class.validation_schema("wat") }.to raise_error(KeyError)
    end
  end

  describe ".build" do
    it "sends the model it was given" do
      item = described_class.build(
        bill: bill, answer_type: described_class::SUMMARY, model: "claude-sonnet-5-5", active_categories: []
      )

      expect(item.model).to eq("claude-sonnet-5-5")
    end

    it "carries the structured-output schema for its answer type" do
      item = described_class.build(
        bill: bill, answer_type: described_class::POSITIONS, model: "claude-sonnet-5-5", active_categories: []
      )

      expect(item.schema).to eq(BILL_POSITIONS_SCHEMA_HASH)
    end

    it "builds a prompt from the bill rather than leaving it empty" do
      item = described_class.build(
        bill: bill, answer_type: described_class::SUMMARY, model: "claude-sonnet-5-5", active_categories: []
      )

      expect(item.prompt.user_message).to include("Section 1.")
    end

    it "captures a testimony snapshot and includes commentary in prompt for positions on commentary-eligible bills" do
      news_article = create(:news_article, :op_ed, outlet_name: "The Sun", title: "Editorial Support")
      text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: "The city council must vote in favor of this bill.")
      bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version, stance: "support")

      item = described_class.build(
        bill: bill, answer_type: described_class::POSITIONS, model: "claude-sonnet-5-5", active_categories: []
      )

      expect(item.prompt.user_message).to include("The city council must vote in favor of this bill.")
      snapshot = bill.news_article_source_snapshots.for_testimony.first
      expect(snapshot).to be_present
      expect(snapshot.source_entries.first["bill_news_article_id"]).to eq(bna.id)
    end

    it "captures a summary-purpose snapshot and includes reporting in prompt for positions on reporting-eligible bills" do
      news_article = create(:news_article, outlet_name: "The Baltimore Banner", title: "Housing Story")
      text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: "The director stated: \"This will protect tenant families.\"")
      bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

      item = described_class.build(
        bill: bill, answer_type: described_class::POSITIONS, model: "claude-sonnet-5-5", active_categories: []
      )

      expect(item.prompt.user_message).to include("This will protect tenant families.")
      snapshot = bill.news_article_source_snapshots.for_summary.first
      expect(snapshot).to be_present
      expect(snapshot.source_entries.first["bill_news_article_id"]).to eq(bna.id)
    end

    it "includes both commentary and reporting snapshots when both are present" do
      op_ed = create(:news_article, :op_ed, outlet_name: "The Sun", title: "Editorial Support")
      op_ed_tv = create(:news_article_text_version, :extracted, news_article: op_ed, text: "The city council must vote in favor of this bill.")
      create(:bill_news_article, :approved, bill: bill, news_article: op_ed, current_text_version: op_ed_tv, stance: "support")

      reporting = create(:news_article, outlet_name: "The Banner", title: "Reporting Story")
      reporting_tv = create(:news_article_text_version, :extracted, news_article: reporting, text: "The spokesperson said: \"We welcome this change.\"")
      create(:bill_news_article, :approved, bill: bill, news_article: reporting, current_text_version: reporting_tv)

      item = described_class.build(
        bill: bill, answer_type: described_class::POSITIONS, model: "claude-sonnet-5-5", active_categories: []
      )

      expect(item.prompt.user_message).to include("The city council must vote in favor of this bill.")
      expect(item.prompt.user_message).to include("We welcome this change.")
      expect(bill.news_article_source_snapshots.for_testimony.count).to eq(1)
      expect(bill.news_article_source_snapshots.for_summary.count).to eq(1)
    end

    it "refuses an answer type it has no prompt builder for" do
      expect {
        described_class.build(bill: bill, answer_type: "wat", model: "m", active_categories: [])
      }.to raise_error(ArgumentError, /wat/)
    end
  end

  describe ".build_all" do
    def item_eligibility_for(a_bill)
      SummaryItemEligibility.for(
        bill: a_bill, provisioning: BillLlmProvisioning.find_by!(bill_id: a_bill.id)
      )
    end

    it "builds both items for a bill with source text and testimony" do
      create(:bill_llm_provisioning, :with_testimony, bill: bill)

      items = described_class.build_all(
        bill: bill.reload, eligibility: item_eligibility_for(bill), model: "m", active_categories: []
      )

      expect(items.map(&:custom_id)).to eq(["bill__#{bill.id}__summary", "bill__#{bill.id}__positions"])
    end

    it "builds only the summary item for a bill with no testimony" do
      create(:bill_llm_provisioning, bill: bill)

      items = described_class.build_all(
        bill: bill.reload, eligibility: item_eligibility_for(bill), model: "m", active_categories: []
      )

      expect(items.map(&:custom_id)).to eq(["bill__#{bill.id}__summary"])
    end

    it "builds both items for a bill with source text and commentary even without hearing testimony" do
      create(:bill_llm_provisioning, bill: bill)
      news_article = create(:news_article, :op_ed)
      text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: "The council should approve this bill.")
      create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version, stance: "support")

      items = described_class.build_all(
        bill: bill.reload, eligibility: item_eligibility_for(bill), model: "m", active_categories: []
      )

      expect(items.map(&:custom_id)).to eq(["bill__#{bill.id}__summary", "bill__#{bill.id}__positions"])
    end

    it "builds both items for a bill with source text and approved reporting even without hearing testimony or commentary" do
      create(:bill_llm_provisioning, bill: bill)
      news_article = create(:news_article)
      text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: "The president stated: \"We endorse this reform.\"")
      create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

      items = described_class.build_all(
        bill: bill.reload, eligibility: item_eligibility_for(bill), model: "m", active_categories: []
      )

      expect(items.map(&:custom_id)).to eq(["bill__#{bill.id}__summary", "bill__#{bill.id}__positions"])
    end

    it "builds nothing for a bill with neither" do
      bare = create(:bill, external_id: "SBI-BARE", sway_locale: sway_locale,
        extracted_text: nil, scheduled_release_date_utc: 701.days.ago)
      create(:bill_llm_provisioning, bill: bare)

      items = described_class.build_all(
        bill: bare.reload, eligibility: item_eligibility_for(bare), model: "m", active_categories: []
      )

      expect(items).to be_empty
    end
  end

  describe "submission attempt isolation and snapshot reuse" do
    let(:news_article) { create(:news_article, :op_ed, outlet_name: "The Sun", title: "Editorial Support") }
    let(:text_version) { create(:news_article_text_version, :extracted, news_article: news_article, text: "The city council must vote in favor of this bill.") }
    let!(:bna) { create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version, stance: "support") }

    it "captures distinct snapshots for separate submission attempts on the same bill" do
      described_class.build(
        bill: bill, answer_type: described_class::SUMMARY, model: "claude-sonnet-5-5",
        active_categories: [], run_receipt: "batch:pending:run_1:#{bill.id}"
      )
      described_class.build(
        bill: bill, answer_type: described_class::SUMMARY, model: "claude-sonnet-5-5",
        active_categories: [], run_receipt: "batch:pending:run_2:#{bill.id}"
      )

      snapshots = bill.news_article_source_snapshots.for_summary.to_a
      expect(snapshots.count).to eq(2)
      expect(snapshots.first.id).not_to eq(snapshots.second.id)
      expect(snapshots.map(&:run_receipt)).to contain_exactly("batch:pending:run_1:#{bill.id}", "batch:pending:run_2:#{bill.id}")
    end

    it "reuses the same snapshot on retry of the same submission attempt" do
      described_class.build(
        bill: bill, answer_type: described_class::SUMMARY, model: "claude-sonnet-5-5",
        active_categories: [], run_receipt: "batch:pending:run_1:#{bill.id}"
      )
      described_class.build(
        bill: bill, answer_type: described_class::SUMMARY, model: "claude-sonnet-5-5",
        active_categories: [], run_receipt: "batch:pending:run_1:#{bill.id}"
      )

      expect(bill.news_article_source_snapshots.for_summary.count).to eq(1)
    end

    it "reuses both summary and testimony snapshots on repeated SummaryBatchItem.build_all calls with the same run_receipt" do
      provisioning = create(:bill_llm_provisioning, bill: bill)
      eligibility = SummaryItemEligibility.for(bill: bill.reload, provisioning: provisioning)
      expect(eligibility.summary?).to be(true)
      expect(eligibility.positions?).to be(true)

      2.times do
        items = described_class.build_all(
          bill: bill, eligibility: eligibility, model: "claude-sonnet-5-5",
          active_categories: [], run_receipt: "batch:pending:run_all:#{bill.id}"
        )
        expect(items.length).to eq(2)
      end

      expect(bill.news_article_source_snapshots.for_summary.where(run_receipt: "batch:pending:run_all:#{bill.id}").count).to eq(1)
      expect(bill.news_article_source_snapshots.for_testimony.where(run_receipt: "batch:pending:run_all:#{bill.id}").count).to eq(1)
    end
  end
end
