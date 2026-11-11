# frozen_string_literal: true

require "rails_helper"

RSpec.describe Eval::VerdictGate do
  let(:manifest_entry) do
    {
      "external_id" => "25-0064",
      "answer_type" => "positions",
      "system_prompt_sha256" => "system-hash-current",
      "user_message_sha256" => "user-hash-current"
    }
  end

  let(:answer) do
    {
      "model_id" => "unsloth/gemma-4-26B-A4B-it-GGUF:UD-Q4_K_M",
      "system_prompt_sha256" => "system-hash-current",
      "user_message_sha256" => "user-hash-current",
      "session_id" => nil
    }
  end

  let(:verdict) do
    {
      "judge_model" => "claude-sonnet-5-5",
      "session_id" => "session-abc"
    }
  end

  describe ".admit!" do
    it "returns true when the judge differs from the answered model and both hashes match" do
      expect(described_class.admit!(verdict: verdict, answer: answer, manifest_entry: manifest_entry)).to be true
    end

    it "raises SelfGradedError naming the bill, the answer type and the model when the judge equals the answer's model" do
      self_graded_verdict = verdict.merge("judge_model" => answer.fetch("model_id"))

      expect { described_class.admit!(verdict: self_graded_verdict, answer: answer, manifest_entry: manifest_entry) }
        .to raise_error(Eval::VerdictGate::SelfGradedError) { |error|
          expect(error.message).to include("25-0064").and include("positions").and include(answer.fetch("model_id"))
        }
    end

    it "raises StaleAnswerError naming the bill, the answer type and the model when the system prompt hash no longer matches" do
      stale_answer = answer.merge("system_prompt_sha256" => "a-hash-the-manifest-no-longer-carries")

      expect { described_class.admit!(verdict: verdict, answer: stale_answer, manifest_entry: manifest_entry) }
        .to raise_error(Eval::VerdictGate::StaleAnswerError) { |error|
          expect(error.message).to include("25-0064").and include("positions").and include(answer.fetch("model_id"))
        }
    end

    it "raises StaleAnswerError when the user message hash no longer matches" do
      stale_answer = answer.merge("user_message_sha256" => "a-hash-the-manifest-no-longer-carries")

      expect { described_class.admit!(verdict: verdict, answer: stale_answer, manifest_entry: manifest_entry) }
        .to raise_error(Eval::VerdictGate::StaleAnswerError)
    end

    it "never includes payload content in either error message, only the record's identifying names" do
      self_graded_verdict = verdict.merge("judge_model" => answer.fetch("model_id"))

      expect { described_class.admit!(verdict: self_graded_verdict, answer: answer, manifest_entry: manifest_entry) }
        .to raise_error(Eval::VerdictGate::SelfGradedError) { |error|
          expect(error.message).not_to include("system-hash-current")
          expect(error.message).not_to include("user-hash-current")
        }
    end

    it "returns true and does not raise when the verdict's session_id equals the answer's session_id" do
      same_session_answer = answer.merge("session_id" => "shared-session-id")
      same_session_verdict = verdict.merge("session_id" => "shared-session-id")

      expect(described_class.admit!(verdict: same_session_verdict, answer: same_session_answer, manifest_entry: manifest_entry))
        .to be true
    end
  end
end
