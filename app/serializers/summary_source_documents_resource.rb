# frozen_string_literal: true

# @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
class SummarySourceDocumentsResource < ApplicationResource
  attributes :origin, :bill_details, :source_text, :citations, :news

  attribute :built_at do |documents|
    documents.built_at&.iso8601
  end
end
