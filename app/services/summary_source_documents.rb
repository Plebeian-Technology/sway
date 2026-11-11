# frozen_string_literal: true

# @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
class SummarySourceDocuments
  RUN_ORIGIN = "run"
  NOW_ORIGIN = "now"

  Result = Data.define(:origin, :built_at, :bill_details, :source_text, :citations, :news)

  def self.call(bill:)
    row = bill.bill_summary_prompt_snapshot
    return from_row(row) if row

    from_builder(bill)
  end

  def self.from_row(row)
    Result.new(
      origin: RUN_ORIGIN,
      built_at: row.built_at,
      bill_details: row.bill_details_text,
      source_text: row.source_text,
      citations: row.citations_text,
      news: row.news_text
    )
  end
  private_class_method :from_row

  def self.from_builder(bill)
    snapshot = BillSummaryPromptBuilder.new(bill).snapshot
    Result.new(
      origin: NOW_ORIGIN,
      built_at: nil,
      bill_details: snapshot.bill_details_text,
      source_text: snapshot.source_text,
      citations: snapshot.citations_text,
      news: snapshot.news_text
    )
  end
  private_class_method :from_builder
end
