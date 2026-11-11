# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-stance-classification#Testimony stance classification#Payload schema specification]]
  class StanceClassifier
    STANCES = %w[support oppose neutral].freeze
    MAX_LETTERS_PER_BATCH = 25
    MIN_DECISION_CONFIDENCE = 0.5
    CLASSIFIER_MODEL = "claude-haiku-5-5"

    def self.build(llm: :default, purpose: :classification)
      return new(llm: llm, purpose: purpose) unless llm == :default
      return new(llm: nil, purpose: purpose) if Rails.env.test?

      route = Llm::RouteResolver.resolve(purpose: purpose, blank_fallback: CLASSIFIER_MODEL)
      new(llm: Llm::Client.build(provider: route.provider.to_s), route: route, purpose: purpose)
    rescue => e
      SwayLogging.warn(
        "stance_classifier.adapter_unavailable",
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      new(llm: nil, purpose: purpose)
    end

    def initialize(llm: nil, enabled: nil, route: nil, purpose: :classification)
      @llm = llm
      @route = route
      @purpose = purpose
      @enabled = enabled.nil? ? !llm.nil? : enabled
    end

    def call(text:, letters:, bill: nil)
      return [[], empty_counts] if letters.empty?

      full_text = text.to_s
      unless enabled? && !llm.nil?
        augmented = letters.map do |letter|
          if manual_override?(letter)
            letter
          elsif excluded_letter?(letter)
            stance = (letter["stance"] || letter[:stance]).to_s
            letter.merge("stance" => STANCES.include?(stance) ? stance : "neutral")
          else
            letter.merge("stance" => rule_stance_for(full_text, letter) || "neutral")
          end
        end
        return [augmented, stance_counts(augmented)]
      end

      adapter = llm
      results_by_position = {}
      eligible = letters.reject { |letter| manual_override?(letter) || excluded_letter?(letter) }
      eligible.each_slice(MAX_LETTERS_PER_BATCH) do |batch|
        results_by_position.merge!(model_results(full_text, batch, adapter, bill))
      end

      augmented = letters.map do |letter|
        if manual_override?(letter)
          letter
        elsif excluded_letter?(letter)
          stance = (letter["stance"] || letter[:stance]).to_s
          letter.merge("stance" => STANCES.include?(stance) ? stance : "neutral")
        else
          pos = letter["position"] || letter[:position]
          model_stance = results_by_position[pos]
          rule_stance = rule_stance_for(full_text, letter)
          stance = if model_stance.present? && model_stance != "neutral"
            model_stance
          else
            rule_stance || model_stance || "neutral"
          end
          letter.merge("stance" => stance)
        end
      end

      [augmented, stance_counts(augmented)]
    end

    private

    attr_reader :llm

    def enabled?
      @enabled
    end

    def empty_counts
      {
        "stance_support_count" => 0,
        "stance_oppose_count" => 0,
        "stance_neutral_count" => 0
      }
    end

    def stance_counts(augmented)
      active = augmented.reject { |l| excluded_letter?(l) }
      {
        "stance_support_count" => active.count { |l| l["stance"] == "support" },
        "stance_oppose_count" => active.count { |l| l["stance"] == "oppose" },
        "stance_neutral_count" => active.count { |l| l["stance"] != "support" && l["stance"] != "oppose" }
      }
    end

    def manual_override?(letter)
      override = letter["stance_override"] || letter[:stance_override]
      stance = (letter["stance"] || letter[:stance]).to_s
      override == true && STANCES.include?(stance)
    end

    def excluded_letter?(letter)
      letter["excluded"] == true || letter[:excluded] == true
    end

    def raw_letter_slice(full_text, letter)
      offset = letter["character_offset"] || letter[:character_offset]
      length = letter["characters"] || letter[:characters]
      if offset && length
        offset_i = offset.to_i
        length_i = length.to_i
        return "" if offset_i < 0 || length_i <= 0

        full_text[offset_i, length_i].to_s
      else
        (letter["text"] || letter[:text] || "").to_s
      end
    end

    def rule_stance_for(full_text, letter)
      Testimony::StanceRules.classify(raw_letter_slice(full_text, letter))
    end

    def letter_text_for(full_text, letter)
      raw = raw_letter_slice(full_text, letter)
      return "" if raw.empty?

      if letter.key?("character_offset") || letter.key?(:character_offset)
        stripped = Testimony::ExtractedText.strip_recipient_headers(
          Testimony::ExtractedText.strip_envelope(raw.lstrip)
        ).strip
        stripped.presence || raw
      else
        raw
      end
    end

    def sanitize_letter_text(text)
      scrubbed = Sway::Utf8.scrub(text.to_s)
      collapsed = Llm::UntrustedTextBlock.neutralize(Llm::PromptLabel.collapse(scrubbed))
      return collapsed if collapsed.length <= Testimony::StancePromptBuilder::MAX_LETTER_CHARS

      head = collapsed[0, Testimony::StancePromptBuilder::HEAD_LETTER_CHARS].to_s
      tail = collapsed[-Testimony::StancePromptBuilder::TAIL_LETTER_CHARS, Testimony::StancePromptBuilder::TAIL_LETTER_CHARS].to_s
      "#{head}#{Testimony::StancePromptBuilder::TEXT_TRUNCATION_NOTICE} #{tail}"
    end

    def decision_model_route?(adapter)
      route = @route
      is_decision = route ? route.decision_model? : Llm::ModelCatalog.decision_model?(model_for(adapter))
      is_decision && adapter.respond_to?(:generate_decisions)
    end

    def model_results(full_text, batch, adapter, bill)
      if decision_model_route?(adapter) && !adapter.is_a?(Llm::ClaudeAdapter) && !adapter.is_a?(Llm::LlamacppAdapter)
        model_results_via_decisions(full_text, batch, adapter, bill)
      else
        model_results_via_chat(full_text, batch, adapter, bill)
      end
    rescue => e
      SwayLogging.warn(
        "stance_classifier.llm_failure",
        candidate_count: batch.length,
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      fallback_batch(batch, full_text)
    end

    def sanitize_bill_field(value, max_chars: Testimony::StancePromptBuilder::MAX_SUMMARY_CHARS)
      scrubbed = Sway::Utf8.scrub(value.to_s)
      collapsed = Llm::UntrustedTextBlock.neutralize(Llm::PromptLabel.collapse(scrubbed))
      collapsed[0, max_chars].to_s
    end

    def model_results_via_decisions(full_text, batch, adapter, bill)
      state = {}
      questions = {}
      bill_desc = if bill
        ext_id = sanitize_bill_field(bill.external_id, max_chars: Testimony::StancePromptBuilder::MAX_EXTERNAL_ID_CHARS)
        title = sanitize_bill_field(bill.title, max_chars: Testimony::StancePromptBuilder::MAX_TITLE_CHARS)
        raw_summary = bill.respond_to?(:summary) ? bill.summary : nil
        summary = if raw_summary.present? && raw_summary.to_s.strip != Bill::SUMMARY_PLACEHOLDER
          sanitize_bill_field(raw_summary, max_chars: Testimony::StancePromptBuilder::MAX_SUMMARY_CHARS)
        else
          ""
        end
        header_part = if ext_id.present? && title.present?
          " for #{ext_id} (#{title})"
        elsif ext_id.present?
          " for #{ext_id}"
        elsif title.present?
          " for (#{title})"
        else
          ""
        end
        summary.present? ? "#{header_part} — #{summary}" : header_part
      else
        ""
      end

      batch.each do |letter|
        position = letter["position"] || letter[:position]
        key = "letter_#{position}"
        raw_text = letter_text_for(full_text, letter)
        state[key] = sanitize_letter_text(raw_text)
        questions[key] = {
          "type" => "choice",
          "instructions" => "Determine the stance of letter #{position} toward the bill#{bill_desc}: whether it supports the bill, opposes the bill, or is neutral.",
          "criteria" => {
            "support" => "Urges passage, favorable report, or vote for the bill, including support with amendments, 'vote yes', 'pass this bill', or writing in support.",
            "oppose" => "Urges rejection, unfavorable report, or vote against the bill, including 'vote no', 'please vote no or at least abstain', 'do not pass', 'do not support', or writing in opposition.",
            "neutral" => "Informational testimony, agency fiscal notes, or letters taking no discernible side."
          }
        }
      end

      response =
        begin
          adapter.generate_decisions(
            model: model_for(adapter),
            state: state,
            questions: questions
          )
        rescue => e
          SwayLogging.warn(
            "stance_classifier.llm_failure",
            candidate_count: batch.length,
            error_class: e.class.name,
            message: e.message.to_s[0, 300]
          )
          return fallback_batch(batch, full_text)
        end

      raise TypeError, "Expected Hash response from decision adapter, got #{response.class.name}" unless response.is_a?(Hash)

      raw_answers = response["answers"] || response[:answers]
      answers = raw_answers.is_a?(Hash) ? raw_answers : {}
      results = fallback_batch(batch, full_text)

      batch.each do |letter|
        position = letter["position"] || letter[:position]
        key = "letter_#{position}"
        answer = answers[key] || answers[key.to_sym]
        next unless answer.is_a?(Hash)

        choice = (answer["choice"] || answer[:choice]).to_s
        next unless STANCES.include?(choice)

        probs = answer["probabilities"] || answer[:probabilities]
        choice_prob = probs.is_a?(Hash) ? (probs[choice] || probs[choice.to_sym]) : nil
        raw_conf = answer["confidence"] || answer[:confidence] || choice_prob

        next unless raw_conf.is_a?(Numeric) && raw_conf.to_f.finite? && raw_conf.to_f >= MIN_DECISION_CONFIDENCE

        results[position] = choice
      end

      results
    rescue => e
      SwayLogging.warn(
        "stance_classifier.verdict_application_failed",
        candidate_count: batch.length,
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      fallback_batch(batch, full_text)
    end

    def model_results_via_chat(full_text, batch, adapter, bill)
      candidates = batch.map do |letter|
        pos = letter["position"] || letter[:position]
        {position: pos, text: letter_text_for(full_text, letter)}
      end
      builder = Testimony::StancePromptBuilder.new(letters: candidates, bill: bill)
      payload = Llm::PromptPayload.new(system_prompt: builder.system_prompt, user_message: builder.user_message)

      extra_kwargs = {}
      if (effort = @route&.reasoning_effort).present? && adapter.provider_label == "openrouter"
        extra_kwargs[:reasoning_effort] = effort
      end

      parsed =
        begin
          adapter.generate_testimony_stance_classification(
            prompt: payload,
            model: model_for(adapter),
            schema: TESTIMONY_STANCE_CLASSIFICATION_SCHEMA_HASH,
            **extra_kwargs
          )
        rescue => e
          SwayLogging.warn(
            "stance_classifier.llm_failure",
            candidate_count: batch.length,
            error_class: e.class.name,
            message: e.message.to_s[0, 300]
          )
          return fallback_batch(batch, full_text)
        end

      apply_chat_classifications(batch, parsed["classifications"], full_text)
    rescue => e
      SwayLogging.warn(
        "stance_classifier.verdict_application_failed",
        candidate_count: batch.length,
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      fallback_batch(batch, full_text)
    end

    def apply_chat_classifications(batch, classifications, full_text = "")
      results = fallback_batch(batch, full_text)
      return results unless classifications.is_a?(::Array)

      asked = batch.map { |letter| letter["position"] || letter[:position] }.to_set
      written_positions = Set.new

      classifications.each do |entry|
        next unless entry.is_a?(::Hash)

        position = entry["position"] || entry[:position]
        stance = (entry["stance"] || entry[:stance]).to_s
        next unless position.is_a?(::Integer)
        next unless asked.include?(position)
        next unless STANCES.include?(stance)

        warn_duplicate_position(position) if written_positions.include?(position)
        results[position] = stance
        written_positions << position
      end

      results
    end

    def warn_duplicate_position(position)
      SwayLogging.warn(
        "stance_classifier.duplicate_position_in_batch",
        position: position
      )
    end

    def fallback_batch(batch, full_text = "")
      batch.to_h do |letter|
        pos = letter["position"] || letter[:position]
        [pos, rule_stance_for(full_text, letter) || "neutral"]
      end
    end

    def model_for(adapter)
      resolved_route = @route
      return resolved_route.api_model if resolved_route

      case adapter.provider_label
      when "openrouter"
        route = Llm::RouteResolver.resolve(purpose: @purpose || :classification, blank_fallback: CLASSIFIER_MODEL)
        route.api_model
      when "claude"
        classification_model
      when "llamacpp"
        Sway::Settings.llm.llamacpp_model
      else
        raise ArgumentError, "unknown adapter provider: #{adapter.provider_label.inspect}"
      end
    end

    def classification_model
      @classification_model ||= resolve_classification_model
    end

    def resolve_classification_model
      AdminSetting.singleton.classification_model.presence || CLASSIFIER_MODEL
    rescue => e
      SwayLogging.warn(
        "stance_classifier.setting_unavailable",
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      CLASSIFIER_MODEL
    end
  end
end
