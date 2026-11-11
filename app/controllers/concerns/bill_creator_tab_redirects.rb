# frozen_string_literal: true

# @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
module BillCreatorTabRedirects
  extend ActiveSupport::Concern

  # @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
  BILL_CREATOR_TAB_TO_PATH_HELPER = {
    "creator" => :creator_bill_creator_path,
    "schedule" => :schedule_bill_creator_path,
    "pipeline" => :pipeline_bill_creator_path,
    "pipeline_llm" => :pipeline_bill_creator_path,
    "summary" => :summary_bill_creator_path,
    "positions" => :positions_bill_creator_path
  }.freeze

  private

  def bill_creator_tab_path(bill_creator_tab, bill_id:, default:, **query)
    helper = BILL_CREATOR_TAB_TO_PATH_HELPER[bill_creator_tab.to_s] || default
    send(helper, id: bill_id, **query)
  end
end
