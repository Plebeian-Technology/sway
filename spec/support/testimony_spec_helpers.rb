# frozen_string_literal: true

# @lat: [[scoping-spec-helper-types#Scope spec helper types]]
module TestimonySpecHelpers
  def max_chars
    BillPositionsPromptBuilder.max_testimony_chars
  end

  def current_digest
    Testimony::CoverageReport.call(bill: bill.reload).digest
  end
end
