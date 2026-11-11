# frozen_string_literal: true

# @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
# @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
class SummarySourcesResource < ApplicationResource
  attributes :summary_model, :summary_provider

  attribute :read do |result|
    read = result.read
    if read.nil?
      nil
    else
      record = SummarySourcesRecordResource.new(read.record).serializable_hash #: Hash[Symbol, untyped]
      record.transform_keys(&:to_s).merge(
        "built_at" => read.built_at&.iso8601,
        "llm_model" => read.llm_model,
        "llm_provider" => read.llm_provider
      )
    end
  end

  attribute :now do |result|
    record = SummarySourcesRecordResource.new(result.now).serializable_hash #: Hash[Symbol, untyped]
    record.transform_keys(&:to_s)
  end

  attribute :summary_generated_at do |result|
    result.summary_generated_at&.iso8601
  end
end
