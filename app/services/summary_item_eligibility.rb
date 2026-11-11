# frozen_string_literal: true

# @lat: [[explanation/llm-summaries#Batch summarisation#One reader decides whether a bill earns a batch item]]
class SummaryItemEligibility
  def self.for(bill:, provisioning:)
    new(bill: bill, provisioning: provisioning)
  end

  def initialize(bill:, provisioning:)
    @bill = bill
    @provisioning = provisioning
  end

  def operator_paste?
    SummaryRunMarker.operator_paste?(provisioning.summary_run_id)
  end

  def summary?
    BillSummaryPromptBuilder.new(bill).source_present?
  end

  def positions?
    hearing_testimony? || commentary_eligible?(bill) || news_reporting_eligible?(bill)
  end

  def hearing_testimony?
    provisioning.testimony_present?
  end

  def commentary_eligible?(target_bill = bill)
    NewsArticleTestimonyService.commentary_eligible?(target_bill)
  end

  def news_reporting_eligible?(target_bill = bill)
    NewsOrgPositionGroundingService.reporting_eligible?(target_bill)
  end

  private

  attr_reader :bill, :provisioning
end
