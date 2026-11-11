# frozen_string_literal: true

# @lat: [[partial-reload-poll-lists#Why the Bill Creator tuples are read out of the TypeScript]]
module BillCreatorPollProps
  SOURCES = {
    "PIPELINE_LLM_ONLY_PROPS" => "app/frontend/components/admin/creator/pipelineLlmOnlyProps.ts",
    "SUMMARY_ONLY_PROPS" => "app/frontend/components/admin/creator/BillCreatorSummary.tsx",
    "POSITIONS_ONLY_PROPS" => "app/frontend/components/admin/creator/BillCreatorPositions.tsx"
  }.freeze

  class << self
    def pipeline_llm
      names_in("PIPELINE_LLM_ONLY_PROPS")
    end

    def summary
      names_in("SUMMARY_ONLY_PROPS")
    end

    def positions
      names_in("POSITIONS_ONLY_PROPS")
    end

    # @lat: [[partial-reload-poll-lists#Why the Bill Creator tuples are read out of the TypeScript]]
    def names_in(constant)
      path = SOURCES.fetch(constant)
      body = Rails.root.join(path).read
      literal = body[/#{constant}\s*=\s*\[(.*?)\]\s*as const;/m, 1]
      raise "#{path} no longer declares #{constant} as an `as const` array literal" if literal.nil?

      verified_literal = literal #: String
      names = verified_literal.scan(/"([a-z0-9_]+)"/).flatten
      raise "#{path} declares #{constant} with no prop names in it" if names.empty?

      names
    end
  end
end
