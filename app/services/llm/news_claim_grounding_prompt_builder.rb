# frozen_string_literal: true

module Llm
  # @lat: [[news-article-evidence#Grounding decisions]]
  class NewsClaimGroundingPromptBuilder
    PROMPT_VERSION = 2
    MAX_CONTEXT_CHARS = 4_000
    MAX_CANDIDATE_PROSE_CHARS = 2_000
    TEXT_TRUNCATION_NOTICE = " [... truncated: source context bounded for assessment ...]"
    LEADING_TRUNCATION_NOTICE = "[... truncated: source context bounded for assessment ...] "

    attr_reader :claim_text, :evidence_excerpt, :source_context, :candidate_prose, :boundary

    def initialize(claim_text:, evidence_excerpt:, source_context:, candidate_prose: nil)
      @claim_text = claim_text.to_s.strip
      @evidence_excerpt = evidence_excerpt.to_s.strip
      @source_context = source_context.to_s.strip
      @candidate_prose = candidate_prose.to_s.strip.presence
      @boundary = Llm::UntrustedTextBlock.for(:news_articles)
    end

    def build
      Llm::PromptPayload.new(
        system_prompt: system_prompt,
        user_message: user_message
      )
    end

    def system_prompt
      <<~PROMPT.strip
        You are an impartial factual grounding adjudicator for a civic engagement platform.
        Your task is to determine whether factual claims made in legislative summary or commentary prose are logically entailed by and directly grounded in the provided journalistic reporting evidence.

        CRITERIA:
        1. "supported": All evaluated claims made in the candidate text citing this reporting are directly stated by or logically entailed from the evidence excerpt and source context. Faithful paraphrasing and direct logical implications are supported.
        2. "unsupported": Any claim in the candidate text contradicts the source context, invents numbers, dates, quantities, or statistics not found in the evidence, swaps speaker/actor attribution, or asserts facts absent from the reporting.
        3. "indeterminate": The evidence is ambiguous, contradictory, truncated, or insufficient to reach a conclusive judgment.

        OUTPUT FORMAT:
        You must return a single JSON object with exact keys:
        - "verdict": one of "supported", "unsupported", or "indeterminate"
        - "reason": concise explanation (under 500 characters) citing the specific evidence alignment or discrepancy.
      PROMPT
    end

    def user_message
      bounded = bounded_source_context

      subject = if candidate_prose.present? && candidate_prose != claim_text
        "The claim to evaluate, candidate prose, cited news excerpt, and source context"
      else
        "The claim to evaluate, cited news excerpt, and source context"
      end

      instruction = boundary.instruction(
        subject: subject,
        provenance: "untrusted candidate text and third-party journalistic reporting"
      )

      parts = [
        instruction,
        "",
        "CLAIM TO EVALUATE:",
        boundary.wrap(claim_text)
      ]

      if candidate_prose.present? && candidate_prose != claim_text
        bounded_prose = candidate_prose[0, MAX_CANDIDATE_PROSE_CHARS].to_s
        parts.concat([
          "",
          "CANDIDATE NEWS PROSE:",
          boundary.wrap(bounded_prose)
        ])
      end

      parts.concat([
        "",
        "CITED VERBATIM EXCERPT:",
        boundary.wrap(evidence_excerpt),
        "",
        "SOURCE CONTEXT:",
        boundary.wrap(bounded)
      ])

      parts.join("\n")
    end

    private

    def bounded_source_context
      return source_context if source_context.length <= MAX_CONTEXT_CHARS

      target_needle = evidence_excerpt.presence || claim_text
      excerpt_idx = target_needle.present? ? source_context.index(target_needle) : nil
      trailing_notice = TEXT_TRUNCATION_NOTICE
      leading_notice = LEADING_TRUNCATION_NOTICE

      if excerpt_idx.nil? || (excerpt_idx + target_needle.length <= MAX_CONTEXT_CHARS - trailing_notice.length)
        slice_len = MAX_CONTEXT_CHARS - trailing_notice.length
        return (source_context.slice(0, slice_len) || "") + trailing_notice
      end

      available_budget = MAX_CONTEXT_CHARS - leading_notice.length - trailing_notice.length
      excerpt_center = excerpt_idx + (target_needle.length / 2)
      ideal_start = excerpt_center - (available_budget / 2)
      ideal_end = ideal_start + available_budget

      if ideal_start <= 0
        slice_len = MAX_CONTEXT_CHARS - trailing_notice.length
        (source_context.slice(0, slice_len) || "") + trailing_notice
      elsif ideal_end >= source_context.length
        slice_len = MAX_CONTEXT_CHARS - leading_notice.length
        start_idx = [source_context.length - slice_len, 0].max
        leading_notice + (source_context.slice(start_idx, slice_len) || "")
      else
        leading_notice + (source_context.slice(ideal_start, available_budget) || "") + trailing_notice
      end
    end
  end
end
