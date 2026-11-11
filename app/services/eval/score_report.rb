# frozen_string_literal: true

module Eval
  # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
  class ScoreReport
    DIMENSIONS = {
      "summary" => %w[faithful_to_source carries_actual_effect invents_nothing describes_changes_not_final_text],
      "positions" => %w[stance_correct supported_by_submitted_testimony stays_off_bill_text]
    }.freeze

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
    SCORE_VALUES = [0, 1, 2, 3, 4].freeze

    DimensionDistribution = Data.define(:answer_type, :dimension, :candidate_label, :counts, :admitted_count)
    LatencyRecord = Data.define(:external_id, :answer_type, :candidate, :latency_ms)
    ExclusionRecord = Data.define(:external_id, :answer_type, :candidate, :reason)

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
    class Share < Data.define(:count, :total)
      class ZeroTotalError < StandardError; end

      def to_percent_s
        raise ZeroTotalError, "cannot render a share of zero admitted verdicts" if total.zero?

        "#{(100.0 * count / total).round}% (#{count}/#{total})"
      end
    end

    # @lat: [[rbs-signatures#Why a typed spec double is a plain class rather than a Struct]]
    class Result < Data.define(
      :dimension_distributions, :schema_failure_count, :latency_records,
      :unchecked_share, :source_read_share, :same_session_share, :excluded
    )
      def to_markdown
        Eval::ScoreReport::Renderer.new(self).render
      end
    end

    class << self
      def call(manifest:, answers:, verdicts:, references: [])
        new(manifest: manifest, answers: answers, verdicts: verdicts, references: references).call
      end

      # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why sway:eval tasks stay thin over Eval:: services]]
      # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
      def load_fixtures(root)
        Dir.glob(root.join("*", "*", "*.json")).sort.map { |path| load_fixture_file(root, path) }
      end

      def load_fixture_file(root, path)
        relative = Pathname.new(path).relative_path_from(root)
        external_id, answer_type, candidate_file = relative.to_s.split("/")
        raise "unexpected fixture path shape: #{relative}" if candidate_file.nil?
        checked_candidate_file = candidate_file #: String

        candidate = File.basename(checked_candidate_file, ".json")

        JSON.parse(File.read(path)).merge(
          "external_id" => external_id, "answer_type" => answer_type, "candidate" => candidate
        )
      end
    end

    def initialize(manifest:, answers:, verdicts:, references:)
      @manifest = manifest
      @answers = answers
      @verdicts = verdicts
      @references = references
    end

    def call
      Result.new(
        dimension_distributions: dimension_distributions,
        schema_failure_count: schema_failure_count,
        latency_records: latency_records,
        unchecked_share: share_where { |v, _a| v.fetch("reference_checked") == false },
        source_read_share: share_where { |v, _a| v.fetch("source_read") == true },
        same_session_share: share_where { |v, a| !v.fetch("session_id").nil? && v.fetch("session_id") == a.fetch("session_id") },
        excluded: excluded
      )
    end

    private

    attr_reader :manifest, :answers, :verdicts, :references

    def answers_index
      @answers_index ||= answers.index_by { |answer| identity_key(answer) }
    end

    def identity_key(record)
      [record.fetch("external_id"), record.fetch("answer_type"), record.fetch("candidate")]
    end

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
    def partitioned_verdicts
      @partitioned_verdicts ||= begin
        admitted = []
        rejected = []

        verdicts.each do |verdict|
          key = identity_key(verdict)
          answer = answers_index[key]
          manifest_entry = manifest["#{key[0]}/#{key[1]}"]

          if answer.nil? || manifest_entry.nil?
            rejected << ExclusionRecord.new(
              external_id: key[0], answer_type: key[1], candidate: key[2],
              reason: "#{key[0]}/#{key[1]}/#{key[2]}: no matching answer fixture or manifest entry found"
            )
            next
          end

          begin
            Eval::VerdictGate.admit!(verdict: verdict, answer: answer, manifest_entry: manifest_entry)
            admitted << [verdict, answer]
          rescue Eval::VerdictGate::SelfGradedError, Eval::VerdictGate::StaleAnswerError => e
            rejected << ExclusionRecord.new(external_id: key[0], answer_type: key[1], candidate: key[2], reason: e.message)
          end
        end

        [admitted, rejected]
      end
    end

    def admitted_pairs
      partitioned_verdicts.first
    end

    def excluded
      partitioned_verdicts.last
    end

    def dimension_distributions
      admitted_pairs
        .flat_map { |verdict, answer| verdict.fetch("scores").keys.map { |dimension| [dimension, verdict, answer] } }
        .group_by { |dimension, _verdict, answer| [answer.fetch("answer_type"), dimension] }
        .map { |(answer_type, dimension), rows| build_distribution(answer_type, dimension, rows) }
    end

    def build_distribution(answer_type, dimension, rows)
      counts = SCORE_VALUES.to_h { |value| [value, 0] }
      rows.each { |_dimension, verdict, _answer| counts[verdict.fetch("scores").fetch(dimension)] += 1 }

      candidate_label = rows.map { |_d, _v, answer| "#{answer.fetch("provider")} (#{answer.fetch("model_id")})" }.uniq.join(", ")

      DimensionDistribution.new(
        answer_type: answer_type, dimension: dimension, candidate_label: candidate_label,
        counts: counts, admitted_count: rows.size
      )
    end

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
    def schema_failure_count
      answers.count { |answer| schema_failure?(answer) }
    end

    def schema_failure?(answer)
      Llm::SchemaValidator.parse_and_validate(
        answer.fetch("body"),
        provider_label: answer.fetch("provider"),
        schema: (answer.fetch("answer_type") == "positions") ? BILL_POSITIONS_SCHEMA : BILL_SUMMARY_SCHEMA
      )
      false
    rescue Llm::SchemaError
      true
    end

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
    def latency_records
      answers.map do |answer|
        LatencyRecord.new(
          external_id: answer.fetch("external_id"), answer_type: answer.fetch("answer_type"),
          candidate: answer.fetch("candidate"), latency_ms: answer.fetch("latency_ms")
        )
      end
    end

    def share_where
      pairs = admitted_pairs
      count = pairs.count { |verdict, answer| yield(verdict, answer) }
      Share.new(count: count, total: pairs.size)
    end
  end
end
