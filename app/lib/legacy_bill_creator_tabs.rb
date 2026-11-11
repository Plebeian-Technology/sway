# frozen_string_literal: true

# @lat: [[bill-creator-tab-url-routing#Why LegacyBillCreatorTabs lives in app/lib, not config/routes.rb]]
module LegacyBillCreatorTabs
  URL_SEGMENT_FOR = {
    "creator" => "creator",
    "schedule" => "schedule",
    "pipeline" => "pipeline",
    "pipeline_llm" => "pipeline",
    "summary" => "summary",
    "positions" => "positions"
  }.freeze
end
