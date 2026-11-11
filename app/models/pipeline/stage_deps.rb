# frozen_string_literal: true

module Pipeline
  # @lat: [[legislation-pipeline-stage-deps-graph#Why EMPTY_DEPS carries a steep:ignore]]
  # steep:ignore:start
  EMPTY_DEPS = [].freeze #: Array[String]
  # steep:ignore:end

  STAGE_DEPS = {
    "fetch-bills" => EMPTY_DEPS,
    "fetch-law" => EMPTY_DEPS,
    "extract-text" => %w[fetch-bills].freeze,
    "parse-sections" => %w[extract-text fetch-law].freeze,
    "generate-diffs" => %w[parse-sections].freeze,
    "fetch-hearings" => %w[fetch-bills].freeze,
    "clean-testimony" => %w[fetch-hearings].freeze,
    "summarize-bill" => %w[generate-diffs fetch-hearings clean-testimony].freeze
  }.freeze

  # @lat: [[legislation-pipeline-stage-deps-graph#Why EMPTY_DEPS carries a steep:ignore]]
  # @lat: [[legislation-pipeline#The stage graph]]
  module StageDeps
    # @lat: [[legislation-pipeline-stage-deps-graph#transitive_closure's algorithm notes]]
    def self.transitive_closure(requested_keys)
      visited = Set.new #: Set[String]
      queue = requested_keys.dup
      until queue.empty?
        key = queue.shift #: String?
        next if key.nil?
        next if visited.include?(key)

        visited << key
        STAGE_DEPS.fetch(key, []).each { |dep| queue << dep }
      end
      visited.to_a
    end
  end
end
