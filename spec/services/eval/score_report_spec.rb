# frozen_string_literal: true

require "rails_helper"

RSpec.describe Eval::ScoreReport do
  let(:manifest) do
    {
      "25-0064/positions" => {
        "external_id" => "25-0064",
        "answer_type" => "positions",
        "system_prompt_sha256" => "system-hash",
        "user_message_sha256" => "user-hash"
      }
    }
  end

  let(:valid_body) do
    {"draft_org_positions" => [{"org_name" => "ORG X", "stance" => "support", "summary" => "Because reasons."}]}.to_json
  end

  let(:answer) do
    {
      "external_id" => "25-0064",
      "answer_type" => "positions",
      "candidate" => "llamacpp",
      "model_id" => "some/model",
      "provider" => "llamacpp",
      "produced_by" => "api",
      "session_id" => nil,
      "produced_at" => "2026-08-28T18:05:33Z",
      "system_prompt_sha256" => "system-hash",
      "user_message_sha256" => "user-hash",
      "latency_ms" => 5000,
      "body" => valid_body
    }
  end

  let(:verdict) do
    {
      "external_id" => "25-0064",
      "answer_type" => "positions",
      "candidate" => "llamacpp",
      "judge_model" => "claude-sonnet-5-5",
      "produced_by" => "claude-code-session",
      "session_id" => "judging-session",
      "produced_at" => "2026-08-28T18:15:12Z",
      "scores" => {"supported_by_submitted_testimony" => 3},
      "justifications" => {"supported_by_submitted_testimony" => "mostly grounded"},
      "anchored_on_reference" => nil,
      "reference_checked" => false,
      "source_read" => true
    }
  end

  describe "::DIMENSIONS" do
    it "names seven dimensions across the summary and positions answer types" do
      expect(described_class::DIMENSIONS).to be_frozen
      expect(described_class::DIMENSIONS.values.sum(&:size)).to eq(7)
      expect(described_class::DIMENSIONS.fetch("positions")).to include("supported_by_submitted_testimony")
    end
  end

  describe "::SCORE_VALUES" do
    it "is the frozen integer scale 0 through 4" do
      expect(described_class::SCORE_VALUES).to eq([0, 1, 2, 3, 4])
      expect(described_class::SCORE_VALUES).to be_frozen
    end
  end

  describe ".call" do
    it "aggregates an admitted verdict into a per-dimension distribution, never a mean" do
      result = described_class.call(manifest: manifest, answers: [answer], verdicts: [verdict], references: [])

      distribution = result.dimension_distributions.find { |d| d.dimension == "supported_by_submitted_testimony" }
      expect(distribution.counts).to eq({0 => 0, 1 => 0, 2 => 0, 3 => 1, 4 => 0})
      expect(distribution.admitted_count).to eq(1)
      expect(result).not_to respond_to(:mean)
      expect(result).not_to respond_to(:average)
      expect(result).not_to respond_to(:total)
    end

    it "excludes and names a self-graded verdict rather than scoring it" do
      self_graded_verdict = verdict.merge("judge_model" => answer.fetch("model_id"))

      result = described_class.call(manifest: manifest, answers: [answer], verdicts: [self_graded_verdict], references: [])

      expect(result.dimension_distributions).to be_empty
      expect(result.excluded.size).to eq(1)
      expect(result.excluded.first.reason).to include("25-0064").and include("positions")
    end

    it "excludes and names a verdict whose answer hashes no longer match the manifest" do
      stale_answer = answer.merge("system_prompt_sha256" => "a-hash-the-manifest-no-longer-carries")

      result = described_class.call(manifest: manifest, answers: [stale_answer], verdicts: [verdict], references: [])

      expect(result.dimension_distributions).to be_empty
      expect(result.excluded.size).to eq(1)
    end

    it "counts a schema-validation failure separately from the dimension scores" do
      broken_answer = answer.merge("body" => "Thinking: not valid JSON at all")
      matching_verdict = verdict

      result = described_class.call(manifest: manifest, answers: [broken_answer], verdicts: [matching_verdict], references: [])

      expect(result.schema_failure_count).to eq(1)
      # the verdict itself still scores -- a schema failure is reported
      # BESIDE the dimension scores, never folded into them and
      # never used to silently drop the verdict.
      expect(result.dimension_distributions.first.admitted_count).to eq(1)
    end

    it "does not tell the reader a schema failure was dropped from the dimension rows" do
      broken_answer = answer.merge("body" => "Thinking: not valid JSON at all")

      markdown = described_class.call(manifest: manifest, answers: [broken_answer], verdicts: [verdict], references: []).to_markdown

      expect(markdown).to include("Schema failures:** 1 answer(s)")
      expect(markdown).not_to match(/excluded from every dimension row/)
    end

    it "does not count a schema-passing answer as a schema failure" do
      result = described_class.call(manifest: manifest, answers: [answer], verdicts: [verdict], references: [])

      expect(result.schema_failure_count).to eq(0)
    end

    it "computes the unchecked, source-read and same-session shares over admitted verdicts" do
      result = described_class.call(manifest: manifest, answers: [answer], verdicts: [verdict], references: [])

      expect(result.unchecked_share.count).to eq(1)
      expect(result.unchecked_share.total).to eq(1)
      expect(result.source_read_share.count).to eq(1)
      expect(result.same_session_share.count).to eq(0)
    end

    it "records a latency entry for every answer, independent of scoring" do
      result = described_class.call(manifest: manifest, answers: [answer], verdicts: [verdict], references: [])

      expect(result.latency_records.first.latency_ms).to eq(5000)
    end
  end

  describe "#to_markdown" do
    it "prints exactly one dimension row naming the candidate, the score distribution, and all three shares on the same line" do
      result = described_class.call(manifest: manifest, answers: [answer], verdicts: [verdict], references: [])

      markdown = result.to_markdown

      dimension_line = markdown.lines.find { |line| line.include?("supported_by_submitted_testimony") && line.start_with?("|") }
      expect(dimension_line).not_to be_nil
      expect(dimension_line).to include("llamacpp").and include("some/model")
      expect(dimension_line).to include("Unchecked").or include("unchecked")
      expect(markdown.scan("supported_by_submitted_testimony").size).to eq(1)
      expect(markdown).not_to match(/(overall|total|average|mean) score/i)
    end

    it "still prints when every admitted verdict rests on an unchecked reference, and says so on the same line" do
      result = described_class.call(manifest: manifest, answers: [answer], verdicts: [verdict], references: [])

      markdown = result.to_markdown
      dimension_line = markdown.lines.find { |line| line.include?("supported_by_submitted_testimony") && line.start_with?("|") }

      expect(dimension_line).to include("100%")
    end
  end
end
