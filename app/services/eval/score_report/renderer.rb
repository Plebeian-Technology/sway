# frozen_string_literal: true

module Eval
  class ScoreReport
    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
    class Renderer
      def initialize(result)
        @result = result
      end

      def render
        <<~MARKDOWN
          # Eval Report

          One row per scored dimension. Every row names, on the same line, the
          share of its admitted verdicts resting on unchecked reference
          material, on a judging session's own report of having read the
          source, and on a judge and an answer produced in the same session --
          three shares of self-reported metadata nothing in this phase can
          independently verify.

          #{dimension_table}

          #{schema_failure_section}

          #{exclusion_section}

          #{latency_section}
        MARKDOWN
      end

      private

      attr_reader :result

      def dimension_table
        return "No dimension has an admitted score yet." if result.dimension_distributions.empty?

        rows = result.dimension_distributions.map { |distribution| dimension_row(distribution) }
        ([header_row, separator_row] + rows).join("\n")
      end

      def header_row
        "| Dimension | Candidate | 0 | 1 | 2 | 3 | 4 | Admitted | Shares |"
      end

      def separator_row
        "|---|---|---|---|---|---|---|---|---|"
      end

      def dimension_row(distribution)
        counts = Eval::ScoreReport::SCORE_VALUES.map { |value| distribution.counts.fetch(value).to_s }
        cells = [
          "#{distribution.answer_type}/#{distribution.dimension}",
          distribution.candidate_label,
          *counts,
          distribution.admitted_count.to_s,
          shares_cell
        ]
        "| #{cells.join(" | ")} |"
      end

      # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
      def shares_cell
        [
          "Unchecked #{result.unchecked_share.to_percent_s}",
          "Source read #{result.source_read_share.to_percent_s}",
          "Same session #{result.same_session_share.to_percent_s}"
        ].join("; ")
      end

      def schema_failure_section
        "**Schema failures:** #{result.schema_failure_count} answer(s) failed " \
          "Llm::SchemaValidator -- counted here, beside the dimension rows above and never " \
          "folded into a score. An answer counted here may still appear in those rows: the " \
          "verdict that graded its content stands on its own."
      end

      def exclusion_section
        return "**Excluded verdicts:** none." if result.excluded.empty?

        lines = result.excluded.map { |record| "- #{record.external_id}/#{record.answer_type}/#{record.candidate}: #{record.reason}" }
        (["**Excluded verdicts (refused by Eval::VerdictGate, never scored):**"] + lines).join("\n")
      end

      def latency_section
        return "**Latency:** no answers recorded." if result.latency_records.empty?

        header = "| Bill | Answer type | Candidate | Latency (ms) |"
        separator = "|---|---|---|---|"
        rows = result.latency_records.map do |record|
          "| #{record.external_id} | #{record.answer_type} | #{record.candidate} | #{record.latency_ms} |"
        end
        (["**Latency** (the shared llama.cpp server's latency measures the machine, not the model):",
          "", header, separator] + rows).join("\n")
      end
    end
  end
end
