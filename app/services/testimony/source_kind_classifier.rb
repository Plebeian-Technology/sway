# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-attachment-rules#Source-kind model confirmation and fallback accounting]]
  class SourceKindClassifier
    RULE_DECIDED_KINDS = %i[public_body person_speaking_for_self].freeze #: Array[Testimony::SourceKindRules::kind]
    MODEL_PASS_KINDS = (Testimony::SourceKindRules::KINDS - RULE_DECIDED_KINDS).freeze
    MIN_DECISION_CONFIDENCE = 0.5

    CLASSIFIER_MODEL = "claude-haiku-5-5"
    MAX_TAIL_LETTERS_PER_BATCH = 25

    # @lat: [[testimony-attachment-rules#Source-kind model confirmation and fallback accounting]]
    def self.build(llm: :default, purpose: :classification)
      return new(llm: llm, purpose: purpose) unless llm == :default
      return new(llm: nil, purpose: purpose) if Rails.env.test?

      route = Llm::RouteResolver.resolve(purpose: purpose, blank_fallback: CLASSIFIER_MODEL)
      new(llm: Llm::Client.build(provider: route.provider.to_s), route: route, purpose: purpose)
    rescue => e
      SwayLogging.warn(
        "source_kind_classifier.adapter_unavailable",
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
      @model_fallback_letters = 0
    end

    def call(text:, letters:)
      full_text = text.to_s
      @model_fallback_letters = 0

      rule_result_by_position = {} #: Hash[Integer, Testimony::SourceKindRules::Result]
      tail_letters = [] #: Array[Hash[String, untyped]]

      letters.each do |letter|
        result = rule_result(full_text, letter)
        rule_result_by_position[letter.fetch("position")] = result
        next if letter["excluded"] == true

        tail_letters << letter if MODEL_PASS_KINDS.include?(result.kind)
      end

      resolved_tail = resolve_tail(full_text, tail_letters, rule_result_by_position)

      augmented = letters.map do |letter|
        position = letter.fetch("position")
        result =
          if letter["excluded"] == true
            raw_result = rule_result_by_position.fetch(position)
            MODEL_PASS_KINDS.include?(raw_result.kind) ? safe_fallback_result : raw_result
          else
            resolved_tail[position] || rule_result_by_position.fetch(position)
          end
        finalize(letter, result)
      end

      [augmented, kind_counts(augmented)]
    end

    private

    attr_reader :llm

    def enabled?
      @enabled
    end

    def rule_result(full_text, letter)
      Testimony::SourceKindRules.classify(letter_text_for(full_text, letter), sender_address: letter["sender_address"])
    end

    def letter_text_for(full_text, letter)
      offset = letter.fetch("character_offset").to_i
      length = letter.fetch("characters").to_i
      full_text[offset, length].to_s
    end

    # @lat: [[testimony-attachment-rules#Source-kind model confirmation and fallback accounting]]
    def resolve_tail(full_text, tail_letters, rule_result_by_position)
      return {} if tail_letters.empty?

      adapter = llm
      unless enabled? && !adapter.nil?
        @model_fallback_letters += tail_letters.length
        return fallback_tail(tail_letters)
      end

      results = {} #: Hash[Integer, Testimony::SourceKindRules::Result]
      tail_letters.each_slice(MAX_TAIL_LETTERS_PER_BATCH) do |batch|
        results.merge!(model_results(full_text, batch, adapter, rule_result_by_position))
      end
      results
    end

    def fallback_tail(tail_letters)
      tail_letters.to_h do |letter|
        [letter.fetch("position"), safe_fallback_result] #: [Integer, Testimony::SourceKindRules::Result]
      end
    end

    def safe_fallback_result
      Testimony::SourceKindRules::Result.new(kind: :person_speaking_for_self, phrase: nil, role: nil, sender: nil, org_name: nil)
    end

    def decision_model_route?(adapter)
      route = @route
      is_decision = route ? route.decision_model? : Llm::ModelCatalog.decision_model?(model_for(adapter))
      is_decision && adapter.respond_to?(:generate_decisions)
    end

    # @lat: [[testimony-attachment-rules#Source-kind model confirmation and fallback accounting]]
    def model_results(full_text, batch, adapter, rule_result_by_position)
      if decision_model_route?(adapter) && !adapter.is_a?(Llm::ClaudeAdapter) && !adapter.is_a?(Llm::LlamacppAdapter)
        model_results_via_decisions(full_text, batch, adapter, rule_result_by_position)
      else
        model_results_via_chat(full_text, batch, adapter, rule_result_by_position)
      end
    end

    def model_results_via_decisions(full_text, batch, adapter, rule_result_by_position)
      state = {}
      questions = {}
      batch.each do |letter|
        position = letter.fetch("position")
        key = "letter_#{position}"
        raw_text = letter_text_for(full_text, letter)
        state[key] = sanitize_letter_text(raw_text)
        questions[key] = {
          "type" => "choice",
          "instructions" => "Determine whether letter #{position} is written by an organization in its own voice, by an individual explicitly writing on behalf of a named organization with a role title, or by a private person speaking only for themselves.",
          "criteria" => {
            "named_organization" => "The letter speaks in the voice of an organization itself ('we', 'our organization') naming the organization as author.",
            "person_speaking_for_org" => "An individual signs the letter with their own name, a role title, and a named organization they represent.",
            "person_speaking_for_self" => "A private resident speaking for themselves, or neither organizational reading is clearly supported."
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
            "source_kind_classifier.llm_failure",
            candidate_count: batch.length,
            error_class: e.class.name,
            message: e.message.to_s[0, 300]
          )
          @model_fallback_letters += batch.length
          return fallback_tail(batch)
        end

      raise TypeError, "Expected Hash response from decision adapter, got #{response.class.name}" unless response.is_a?(Hash)

      raw_answers = response["answers"] || response[:answers]
      answers = raw_answers.is_a?(Hash) ? raw_answers : {}
      classifications = batch.filter_map do |letter|
        position = letter.fetch("position")
        key = "letter_#{position}"
        answer = answers[key] || answers[key.to_sym]
        next unless answer.is_a?(Hash)

        choice = (answer["choice"] || answer[:choice]).to_s
        next unless MODEL_PASS_KINDS.map(&:to_s).include?(choice)

        probs = answer["probabilities"] || answer[:probabilities]
        choice_prob = probs.is_a?(Hash) ? (probs[choice] || probs[choice.to_sym]) : nil
        raw_conf = answer["confidence"] || answer[:confidence] || choice_prob

        next unless raw_conf.is_a?(Numeric) && raw_conf.to_f.finite? && raw_conf.to_f >= MIN_DECISION_CONFIDENCE

        {"position" => position, "kind" => choice}
      end

      apply_classifications(batch, classifications, rule_result_by_position)
    rescue => e
      SwayLogging.warn(
        "source_kind_classifier.verdict_application_failed",
        candidate_count: batch.length,
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      @model_fallback_letters += batch.length
      fallback_tail(batch)
    end

    def model_results_via_chat(full_text, batch, adapter, rule_result_by_position)
      candidates = batch.map do |letter|
        {position: letter.fetch("position"), text: letter_text_for(full_text, letter)} #: Testimony::SourceKindPromptBuilder::candidate
      end
      builder = Testimony::SourceKindPromptBuilder.new(candidates)
      payload = Llm::PromptPayload.new(system_prompt: builder.system_prompt, user_message: builder.user_message)

      extra_kwargs = {}
      if (effort = @route&.reasoning_effort).present? && adapter.provider_label == "openrouter"
        extra_kwargs[:reasoning_effort] = effort
      end

      parsed =
        begin
          adapter.generate_source_kind_classification(
            prompt: payload,
            model: model_for(adapter),
            schema: SOURCE_KIND_CLASSIFICATION_SCHEMA_HASH,
            **extra_kwargs
          )
        rescue => e
          SwayLogging.warn(
            "source_kind_classifier.llm_failure",
            candidate_count: batch.length,
            error_class: e.class.name,
            message: e.message.to_s[0, 300]
          )
          @model_fallback_letters += batch.length
          return fallback_tail(batch)
        end

      apply_classifications(batch, parsed["classifications"], rule_result_by_position)
    rescue => e
      SwayLogging.warn(
        "source_kind_classifier.verdict_application_failed",
        candidate_count: batch.length,
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      @model_fallback_letters += batch.length
      fallback_tail(batch)
    end

    def sanitize_letter_text(text)
      collapsed = Llm::UntrustedTextBlock.neutralize(Llm::PromptLabel.collapse(text.to_s))
      return collapsed if collapsed.length <= Testimony::SourceKindPromptBuilder::MAX_LETTER_CHARS

      collapsed[0, Testimony::SourceKindPromptBuilder::MAX_LETTER_CHARS].to_s + Testimony::SourceKindPromptBuilder::TEXT_TRUNCATION_NOTICE
    end

    # @lat: [[testimony-attachment-rules#Source-kind model confirmation and fallback accounting]]
    def apply_classifications(batch, classifications, rule_result_by_position)
      results = fallback_tail(batch)
      return results unless classifications.is_a?(::Array)

      asked = batch.map { |letter| letter.fetch("position") }.to_set
      written_positions = Set.new #: Set[Integer]
      classifications.each do |entry|
        apply_one_classification(results, rule_result_by_position, asked, entry, written_positions)
      end

      results
    end

    def apply_one_classification(results, rule_result_by_position, asked, entry, written_positions)
      return unless entry.is_a?(::Hash)

      position = entry["position"]
      kind = entry["kind"]
      return unless position.is_a?(::Integer)
      return unless asked.include?(position)
      return unless MODEL_PASS_KINDS.map(&:to_s).include?(kind)

      rule_result = rule_result_by_position.fetch(position, nil)
      return if rule_result.nil?

      # @lat: [[testimony-attachment-rules#Source-kind model confirmation and fallback accounting]]
      if kind == "person_speaking_for_org" && rule_result.kind == :person_speaking_for_org
        warn_duplicate_position(position) if written_positions.include?(position)
        results[position] = rule_result
        written_positions << position
      elsif kind == "named_organization"
        warn_duplicate_position(position) if written_positions.include?(position)
        results[position] = Testimony::SourceKindRules::Result.new(kind: :named_organization, phrase: nil, role: nil, sender: nil, org_name: nil)
        written_positions << position
      end
    end

    def warn_duplicate_position(position)
      SwayLogging.warn(
        "source_kind_classifier.duplicate_position_in_batch",
        position: position
      )
    end

    def finalize(letter, result)
      evidence =
        if result.kind == :person_speaking_for_org
          {"phrase" => result.phrase, "role" => result.role, "sender" => result.sender, "org_name" => result.org_name}
        end

      letter.merge("source_kind" => result.kind.to_s, "source_evidence" => evidence)
    end

    # @lat: [[testimony-attachment-rules#Source-kind model confirmation and fallback accounting]]
    def kind_counts(augmented)
      active = augmented.reject { |letter| letter["excluded"] == true }
      counts = {} #: Hash[String, Integer]
      Testimony::SourceKindRules::KINDS.each do |kind|
        counts["#{kind}_letters"] = active.count { |letter| letter["source_kind"] == kind.to_s }
      end
      counts["source_kind_model_fallbacks"] = @model_fallback_letters
      counts
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
        "source_kind_classifier.setting_unavailable",
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      CLASSIFIER_MODEL
    end
  end
end
