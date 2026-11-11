# frozen_string_literal: true

module Eval
  # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
  module VerdictGate
    class SelfGradedError < StandardError
    end

    class StaleAnswerError < StandardError
    end

    module_function

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#How ScoreReport and VerdictGate aggregate and guard candidate scores]]
    def admit!(verdict:, answer:, manifest_entry:)
      identity = "#{manifest_entry.fetch("external_id")}/#{manifest_entry.fetch("answer_type")}"
      model_id = answer.fetch("model_id")

      if verdict.fetch("judge_model") == model_id
        raise SelfGradedError,
          "#{identity}: judge_model and answer model_id are both #{model_id} -- " \
          "a verdict cannot grade the model that wrote its own answer"
      end

      hashes_match =
        answer.fetch("system_prompt_sha256") == manifest_entry.fetch("system_prompt_sha256") &&
        answer.fetch("user_message_sha256") == manifest_entry.fetch("user_message_sha256")

      unless hashes_match
        raise StaleAnswerError,
          "#{identity}: the answer from #{model_id} carries hashes that no longer match " \
          "eval/manifest.json -- the prompt bytes have moved since this answer was produced"
      end

      true
    end
  end
end
