# frozen_string_literal: true

# @lat: [[bill-creator-summary-tab#Why the panel lists what the model reads]]
class SummaryDiffFacts
  Facts = Data.define(:target, :sections_modified, :sections_referenced_only, :sections_not_found)

  class << self
    def call(provisioning)
      payload = parse(provisioning&.diff_content)
      return empty unless payload.is_a?(Hash)

      stats = payload["stats"]
      stats = {} unless stats.is_a?(Hash)

      Facts.new(
        target: payload["target"]&.to_s,
        sections_modified: integer_or_nil(stats["sections_modified"]),
        sections_referenced_only: integer_or_nil(stats["sections_referenced_only"]),
        sections_not_found: integer_or_nil(stats["sections_not_found"])
      )
    end

    def empty
      Facts.new(target: nil, sections_modified: nil, sections_referenced_only: nil, sections_not_found: nil)
    end

    private

    def parse(raw)
      return nil if raw.blank?

      JSON.parse(raw)
    rescue JSON::ParserError
      nil
    end

    def integer_or_nil(value)
      Integer(value, exception: false)
    end
  end
end
