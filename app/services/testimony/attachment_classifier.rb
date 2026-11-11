# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-attachment-rules#Testimony attachment rules#Classifier routing and cache]]
  class AttachmentClassifier
    CLASSIFIER_MODEL = "claude-haiku-5-5"

    MAX_ATTACHMENTS_PER_BATCH = 25

    KEEP_LABELS = %i[testimony].freeze #: Array[NameRules::label]
    REJECT_LABELS = %i[bill_text procedural].freeze #: Array[NameRules::label]
    MODEL_PASS_LABELS = (Testimony::NameRules::LABELS - KEEP_LABELS - REJECT_LABELS).freeze

    def self.build(llm: :default, purpose: :classification)
      return new(llm: llm, purpose: purpose) unless llm == :default
      return new(llm: nil, purpose: purpose) if Rails.env.test?

      route = Llm::RouteResolver.resolve(purpose: purpose, blank_fallback: CLASSIFIER_MODEL)
      new(llm: Llm::Client.build(provider: route.provider.to_s), route: route, purpose: purpose)
    rescue => e
      SwayLogging.warn(
        "testimony_classifier.adapter_unavailable",
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

    def prefilter(candidates, sway_locale_id:)
      locale_name = locale_name_for(sway_locale_id)
      verdicts = {} #: Hash[Integer, bool]
      undecided = [] #: Array[candidate]

      candidates.each do |candidate|
        label = NameRules.classify(candidate["name"], sway_locale: locale_name)
        if KEEP_LABELS.include?(label)
          verdicts[candidate["id"]] = true
        elsif REJECT_LABELS.include?(label)
          verdicts[candidate["id"]] = false
        else
          cached = cached_label(candidate, sway_locale_id: sway_locale_id)
          if cached.nil?
            undecided << candidate
          else
            verdicts[candidate["id"]] = (cached == TestimonyAttachmentClassification::TESTIMONY)
          end
        end
      end

      {verdicts: verdicts, undecided: undecided}
    end

    def classify_contents(candidates, sway_locale_id:)
      return {} if candidates.empty?

      adapter = llm
      return fallback_verdicts(candidates) unless enabled? && !adapter.nil?

      verdicts = {} #: Hash[Integer, bool]
      candidates.each_slice(MAX_ATTACHMENTS_PER_BATCH) do |batch|
        verdicts.merge!(llm_verdicts(batch, adapter, sway_locale_id: sway_locale_id))
      end
      verdicts
    end

    private

    attr_reader :llm

    def enabled?
      @enabled
    end

    def locale_name_for(sway_locale_id)
      SwayLocale.find_by(id: sway_locale_id)&.name
    rescue => e
      SwayLogging.warn("testimony_classifier.locale_unavailable", error_class: e.class.name)
      nil
    end

    def cached_label(candidate, sway_locale_id:)
      model = current_model
      return nil if model.nil?

      TestimonyAttachmentClassification
        .for_verdict(sway_locale_id, candidate["id"], model, ClassificationPromptBuilder::PROMPT_VERSION)
        .pick(:label)
    rescue => e
      SwayLogging.warn(
        "testimony_classifier.cache_read_failed",
        attachment_id: candidate["id"],
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      nil
    end

    def decision_model_route?(adapter)
      route = @route
      is_decision = route ? route.decision_model? : Llm::ModelCatalog.decision_model?(model_for(adapter))
      is_decision && adapter.respond_to?(:generate_decisions)
    end

    def llm_verdicts(candidates, adapter, sway_locale_id:)
      if decision_model_route?(adapter) && !adapter.is_a?(Llm::ClaudeAdapter) && !adapter.is_a?(Llm::LlamacppAdapter)
        llm_verdicts_via_decisions(candidates, adapter, sway_locale_id: sway_locale_id)
      else
        llm_verdicts_via_chat(candidates, adapter, sway_locale_id: sway_locale_id)
      end
    end

    def llm_verdicts_via_decisions(candidates, adapter, sway_locale_id:)
      state = {}
      questions = {}
      candidates.each_with_index do |candidate, index|
        key = "attachment_#{index}"
        state[key] = {
          "name" => sanitize_name(candidate["name"]),
          "text" => sanitize_text(candidate["text"])
        }
        questions[key] = {
          "type" => "choice",
          "instructions" => "Is attachment #{index} public hearing testimony from a constituent, organization, or agency, or is it not_testimony (bill text, amendment, fiscal note, or procedural notice)?",
          "criteria" => {
            "testimony" => "Written or oral testimony, letters, or position statements submitted for the hearing.",
            "not_testimony" => "Bill text, amendments, fiscal notes, agendas, voting records, or procedural notices."
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
            "testimony_classifier.llm_failure",
            candidate_count: candidates.length,
            error_class: e.class.name,
            message: e.message.to_s[0, 300]
          )
          return fallback_verdicts(candidates)
        end

      raise TypeError, "Expected Hash response from decision adapter, got #{response.class.name}" unless response.is_a?(Hash)

      raw_answers = response["answers"] || response[:answers]
      answers = raw_answers.is_a?(Hash) ? raw_answers : {}
      classifications = candidates.each_with_index.map do |_candidate, index|
        key = "attachment_#{index}"
        ans = answers[key] || answers[key.to_sym]
        choice = ans.is_a?(Hash) ? (ans["choice"] || ans[:choice]) : nil
        {"index" => index, "label" => choice}
      end

      apply_classifications(candidates, classifications, adapter, sway_locale_id: sway_locale_id)
    rescue => e
      SwayLogging.warn(
        "testimony_classifier.verdict_application_failed",
        candidate_count: candidates.length,
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      fallback_verdicts(candidates)
    end

    def llm_verdicts_via_chat(candidates, adapter, sway_locale_id:)
      builder = ClassificationPromptBuilder.new(
        candidates.map { |c| {name: c["name"].to_s, text: c["text"].to_s} }
      )
      payload = Llm::PromptPayload.new(
        system_prompt: builder.system_prompt,
        user_message: builder.user_message
      )

      extra_kwargs = {}
      if (effort = @route&.reasoning_effort).present? && adapter.provider_label == "openrouter"
        extra_kwargs[:reasoning_effort] = effort
      end

      parsed =
        begin
          adapter.generate_testimony_classification(
            prompt: payload,
            model: model_for(adapter),
            schema: TESTIMONY_CLASSIFICATION_SCHEMA_HASH,
            **extra_kwargs
          )
        rescue => e
          SwayLogging.warn(
            "testimony_classifier.llm_failure",
            candidate_count: candidates.length,
            error_class: e.class.name,
            message: e.message.to_s[0, 300]
          )
          return fallback_verdicts(candidates)
        end

      apply_classifications(candidates, parsed["classifications"], adapter, sway_locale_id: sway_locale_id)
    rescue => e
      SwayLogging.warn(
        "testimony_classifier.verdict_application_failed",
        candidate_count: candidates.length,
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      fallback_verdicts(candidates)
    end

    def sanitize_name(name)
      Llm::UntrustedTextBlock.neutralize(
        Llm::PromptLabel.collapse(name.to_s)
      )[0, ClassificationPromptBuilder::MAX_NAME_CHARS].to_s
    end

    def sanitize_text(text)
      collapsed = Llm::UntrustedTextBlock.neutralize(Llm::PromptLabel.collapse(text.to_s))
      return collapsed if collapsed.length <= ClassificationPromptBuilder::MAX_DOCUMENT_CHARS

      collapsed[0, ClassificationPromptBuilder::MAX_DOCUMENT_CHARS].to_s + ClassificationPromptBuilder::TEXT_TRUNCATION_NOTICE
    end

    def apply_classifications(candidates, classifications, adapter, sway_locale_id:)
      verdicts = fallback_verdicts(candidates)
      return verdicts unless classifications.is_a?(::Array)

      classifications.each do |entry|
        apply_one_classification(verdicts, candidates, entry, adapter, sway_locale_id: sway_locale_id)
      end

      verdicts
    end

    def apply_one_classification(verdicts, candidates, entry, adapter, sway_locale_id:)
      return unless entry.is_a?(::Hash)

      index = entry["index"]
      label = entry["label"]
      return unless index.is_a?(::Integer)
      return if index.negative?
      return unless TestimonyAttachmentClassification::LABELS.include?(label)

      candidate = candidates[index] #: content_candidate?
      return if candidate.nil?

      verdicts[candidate["id"]] = (label == TestimonyAttachmentClassification::TESTIMONY)
      persist_verdict(candidate, label.to_s, adapter, sway_locale_id: sway_locale_id)
    rescue => e
      SwayLogging.warn(
        "testimony_classifier.verdict_entry_skipped",
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
    end

    def persist_verdict(candidate, label, adapter, sway_locale_id:)
      record = TestimonyAttachmentClassification.find_or_initialize_by(sway_locale_id: sway_locale_id, attachment_id: candidate["id"])
      record.source_endpoint = candidate["source_endpoint"]
      record.label = label
      record.model = model_for(adapter)
      record.prompt_version = ClassificationPromptBuilder::PROMPT_VERSION
      record.save!
    rescue => e
      SwayLogging.warn(
        "testimony_classifier.cache_write_failed",
        attachment_id: candidate["id"],
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
    end

    def fallback_verdicts(candidates)
      candidates.to_h do |candidate|
        [candidate["id"], true] #: [Integer, bool]
      end
    end

    def current_model
      adapter = llm
      adapter.nil? ? nil : model_for(adapter)
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
        "testimony_classifier.setting_unavailable",
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      CLASSIFIER_MODEL
    end
  end
end
