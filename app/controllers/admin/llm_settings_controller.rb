# frozen_string_literal: true

# @lat: [[admin-llm-settings-singleton-route#Why llm_settings is a singular resource]]
# @lat: [[admin-setting-model-list#Why the inclusion validations are conditional]]
# @lat: [[llm-job-model-resolution-per-perform#Why the model is re-read on every perform, not memoized]]
# @lat: [[admin-llm-settings-controller-design#The admin-namespace convention, and the mass-assignment guard]]
module Admin
  class LlmSettingsController < ApplicationController
    before_action :verify_is_sway_admin

    # @lat: [[admin-llm-settings-controller-design#Why labels live off the model]]
    SUPPORTED_MODEL_LABELS = {
      "claude-haiku-5-5" => "Haiku 5.5 — fast & cheap (default)",
      "claude-sonnet-5-5" => "Sonnet 5.5 — balanced",
      "claude-opus-5-5" => "Opus 5.5 — maximum quality",
      "Opus Latest" => "Opus Latest",
      "Sonnet Latest" => "Sonnet Latest",
      "Haiku Latest" => "Haiku Latest",
      "Gemini Argon Latest" => "Gemini Argon Latest",
      "Gemini Flash Latest" => "Gemini Flash Latest",
      "GLM Latest" => "GLM Latest",
      "Deepseek Pro Latest" => "Deepseek Pro Latest",
      "Deepseek Flash Latest" => "Deepseek Flash Latest",
      "OpenRouter Auto" => "OpenRouter Auto",
      "ScaleDown Classify Latest" => "ScaleDown Classify Latest",
      "ScaleDown Extract Latest" => "ScaleDown Extract Latest",
      "Jev Latest" => "Jev Latest",
      "Perplexity Decider Latest" => "Perplexity Decider Latest",
      "Perplexity Decider Flash Latest" => "Perplexity Decider Flash Latest"
    }.freeze

    REFRESHED_MESSAGE = "OpenRouter model list refreshed."
    MODEL_ADDED_MESSAGE = "Model added to offered list."
    MODEL_REMOVED_MESSAGE = "Model removed from offered list."

    MODEL_FIELDS = %i[summarization_model classification_model decision_model extraction_model].freeze

    # @lat: [[llm-summaries#Batch summarisation#Why the batch path is off until it is switched on]]
    BOOLEAN_FIELDS = %i[summary_batch_enabled].freeze

    BOOLEAN_VALUE_LABELS = {"true" => "on", "false" => "off"}.freeze

    REASONING_FIELDS = %i[summarization_reasoning_effort classification_reasoning_effort].freeze

    WRITABLE_FIELDS = (MODEL_FIELDS + BOOLEAN_FIELDS + REASONING_FIELDS).freeze

    UNRECOGNIZED_MODEL_MESSAGE = "Model not recognized. Choose from the list."

    # @lat: [[admin-llm-settings-controller-design#Why rejected_model_errors's per-column attribution has its own regression test]]
    UNSAVEABLE_MESSAGE = "Could not save. Check the server logs."

    # @lat: [[admin-llm-settings-controller-design#LlmSettings.tsx, the frontend page]]
    UNCHANGED_MESSAGE = "Nothing to update — no setting was changed."

    MODEL_UPDATED_MESSAGE = "Model updated."

    SETTINGS_UPDATED_MESSAGE = "Settings updated."

    def show
      render_inertia_or_json(page: Pages::ADMIN_LLM_SETTINGS, props: show_props)
    end

    # @lat: [[admin-llm-settings-controller-design#Why update's response shapes differ by client]]
    def update
      # @lat: [[admin-setting-model-list#Why the inclusion validations are conditional]]
      submitted = cast_booleans(
        params.require(:admin_setting)
          .permit(WRITABLE_FIELDS)
          .to_h
          .symbolize_keys
      )

      outcome, stale = apply_submitted_models(submitted)

      case outcome
      when :stale then render_stale_conflict(stale)
      when :unchanged then render_settings(notice: UNCHANGED_MESSAGE)
      else render_settings(notice: update_notice(submitted))
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_to do |format|
        format.json do
          render_error(code: "validation_failed", message: json_rejection_message(e.record), status: :unprocessable_content)
        end
        format.html do
          redirect_to admin_llm_settings_path,
            inertia: {errors: {admin_setting: rejected_model_errors(e.record)}}
        end
      end
    end

    # @lat: [[admin-llm-settings-controller-design#Dynamic model catalog and offered model actions]]
    def refresh_models
      Llm::OpenRouterModelsService.call(force_refresh: true)
      Llm::OpenRouterModelsService.decision_models(force_refresh: true)

      respond_to do |format|
        format.html { redirect_to admin_llm_settings_path, notice: REFRESHED_MESSAGE }
        format.json do
          render json: serialized_model_options_payload(AdminSetting.singleton), status: :ok
        end
      end
    end

    # @lat: [[admin-llm-settings-controller-design#Dynamic model catalog and offered model actions]]
    def add_model
      AdminSetting.singleton.add_offered_model!(params.fetch(:model_id, "").to_s, updated_by: current_user)

      respond_to do |format|
        format.html { redirect_to admin_llm_settings_path, notice: MODEL_ADDED_MESSAGE }
        format.json do
          render json: serialized_model_options_payload(AdminSetting.singleton), status: :ok
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_to do |format|
        format.html do
          error_message = e.record.errors.full_messages_for(:offered_models).first || e.message
          redirect_to admin_llm_settings_path, inertia: {errors: {offered_models: error_message}}
        end
        format.json do
          render json: {error: e.message}, status: :unprocessable_content
        end
      end
    end

    # @lat: [[admin-llm-settings-controller-design#Dynamic model catalog and offered model actions]]
    def remove_model
      AdminSetting.singleton.remove_offered_model!(params.fetch(:model_id, "").to_s, updated_by: current_user)

      respond_to do |format|
        format.html { redirect_to admin_llm_settings_path, notice: MODEL_REMOVED_MESSAGE }
        format.json do
          render json: serialized_model_options_payload(AdminSetting.singleton), status: :ok
        end
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_to do |format|
        format.html do
          error_message = e.record.errors.full_messages_for(:offered_models).first || e.message
          redirect_to admin_llm_settings_path, inertia: {errors: {offered_models: error_message}}
        end
        format.json do
          render json: {error: e.message}, status: :unprocessable_content
        end
      end
    end

    private

    # @lat: [[llm-summaries#Batch summarisation#Why the batch path is off until it is switched on]]
    def cast_booleans(fields)
      fields.to_h do |field, value|
        cast = BOOLEAN_FIELDS.include?(field) ? ActiveModel::Type::Boolean.new.cast(value) == true : value
        [field, cast]
      end
    end

    def update_notice(submitted)
      (submitted.keys & MODEL_FIELDS).any? ? MODEL_UPDATED_MESSAGE : SETTINGS_UPDATED_MESSAGE
    end

    # @lat: [[admin-llm-settings-controller-design#Why apply_submitted_models locks the whole read-decide-write]]
    def apply_submitted_models(submitted)
      setting = AdminSetting.singleton

      if submitted[:summarization_reasoning_effort].to_s.strip.present?
        target = (submitted[:summarization_model] || setting.summarization_model).to_s
        Llm::ModelCatalog.supports_reasoning?(target) if target.present?
      end
      if submitted[:classification_reasoning_effort].to_s.strip.present?
        target = (submitted[:classification_model] || setting.classification_model).to_s
        Llm::ModelCatalog.supports_reasoning?(target) if target.present?
      end

      setting.with_lock do
        stale = stale_fields(setting, submitted)
        next [:stale, stale] if stale.any?
        next [:unchanged, stale] if unchanged?(setting, submitted)

        setting.update!(submitted.merge(updated_by_id: current_user.id))
        [:updated, stale]
      end
    end

    def unchanged?(setting, submitted)
      effective_summarization_model = (submitted[:summarization_model] || setting.summarization_model).to_s
      effective_classification_model = (submitted[:classification_model] || setting.classification_model).to_s

      submitted.all? do |field, value|
        normalized_value = case field
        when :summarization_reasoning_effort
          effort = value.to_s.strip.presence
          (effort && effective_summarization_model.present? && !Llm::ModelCatalog.supports_reasoning?(effective_summarization_model)) ? "" : effort.to_s
        when :classification_reasoning_effort
          effort = value.to_s.strip.presence
          (effort && effective_classification_model.present? && !Llm::ModelCatalog.supports_reasoning?(effective_classification_model)) ? "" : effort.to_s
        else
          value.to_s
        end

        setting.public_send(field).to_s == normalized_value
      end
    end

    # @lat: [[admin-llm-settings-controller-design#Why render_settings sends the same JSON body for both outcomes]]
    def render_settings(notice:)
      respond_to do |format|
        format.json do
          render json: AdminSetting.singleton.as_json(
            only: %i[
              summarization_model classification_model decision_model extraction_model
              summary_batch_enabled summarization_reasoning_effort
              classification_reasoning_effort updated_by_id updated_at
            ]
          )
        end
        format.html { redirect_to admin_llm_settings_path, notice: notice }
      end
    end

    # @lat: [[admin-llm-settings-stale-write-race#Why a client with no expected block conflicts with nothing]]
    def stale_fields(setting, submitted)
      expected = params[:admin_setting][:expected]
      return {} unless expected.respond_to?(:permit)

      expected = cast_booleans(expected.permit(WRITABLE_FIELDS).to_h.symbolize_keys)

      submitted.keys.each_with_object({}) do |field, result|
        next unless expected.key?(field)

        was = expected[field] #: (String | bool)?
        next if was.nil? && !REASONING_FIELDS.include?(field)

        current = setting.public_send(field).to_s
        result[field] = current unless was.to_s == current
      end
    end

    # @lat: [[admin-llm-settings-stale-write-race#Why the stale-conflict message is a refusal the admin can act on]]
    def render_stale_conflict(stale)
      respond_to do |format|
        format.json do
          render_error(
            code: "stale_write",
            message: stale.map { |field, current| json_stale_conflict_message(field, current) }.join(" "),
            status: :conflict
          )
        end
        format.html do
          labels = stale.keys.intersect?(MODEL_FIELDS) ? AdminSetting.offered_model_labels : nil
          errors = stale.to_h { |field, current| [field, stale_conflict_message(field, current, labels: labels)] }
          redirect_to admin_llm_settings_path, inertia: {errors: {admin_setting: errors}}
        end
      end
    end

    # @lat: [[admin-llm-settings-stale-write-race#Why the stale-conflict message is a refusal the admin can act on]]
    def stale_conflict_message(field, current_value, labels: nil)
      if BOOLEAN_FIELDS.include?(field)
        label = BOOLEAN_VALUE_LABELS.fetch(current_value, current_value)
        kind = "settings"
      elsif REASONING_FIELDS.include?(field)
        label = current_value.presence || "default"
        kind = "reasoning settings"
      else
        label = label_for_model(current_value, labels: labels)
        kind = "models"
      end
      "Someone else changed this to #{label} since you loaded the page. " \
        "Nothing was saved. Load the current #{kind} from the notice above, then choose again."
    end

    # @lat: [[admin-llm-settings-stale-write-race#Why the stale-conflict message is a refusal the admin can act on]]
    def json_stale_conflict_message(field, current_value)
      display_value = REASONING_FIELDS.include?(field) ? (current_value.presence || "default") : current_value
      "#{field} is now #{display_value}, not the value you sent as expected. Nothing was saved. " \
        "GET /admin/llm_settings for the current settings, then submit again."
    end

    # @lat: [[admin-llm-settings-controller-design#Mapping validation errors to fields]]
    def rejected_model_errors(record)
      errors = MODEL_FIELDS.select { |attr| record.errors.key?(attr) }.index_with { UNRECOGNIZED_MODEL_MESSAGE }

      BOOLEAN_FIELDS.each do |attr|
        next unless record.errors.key?(attr)

        errors[attr] = record.errors.full_messages_for(attr).to_sentence.presence || UNSAVEABLE_MESSAGE
      end

      REASONING_FIELDS.each do |attr|
        next unless record.errors.key?(attr)

        errors[attr] = record.errors.full_messages_for(attr).to_sentence.presence || UNSAVEABLE_MESSAGE
      end
      return errors if errors.any?

      {summarization_model: record.errors.full_messages.to_sentence.presence || UNSAVEABLE_MESSAGE}
    end

    # @lat: [[admin-llm-settings-controller-design#Mapping validation errors to fields]]
    def json_rejection_message(record)
      attributed = MODEL_FIELDS.any? { |attr| record.errors.key?(attr) }
      return "Model not recognized." if attributed

      record.errors.full_messages.to_sentence.presence || UNSAVEABLE_MESSAGE
    end

    def show_props
      setting = AdminSetting.singleton
      updated_by_user = setting.updated_by
      catalog_models = begin
        Llm::OpenRouterModelsService.call
      rescue => e
        Rails.logger.warn("Admin::LlmSettingsController show_props failed to fetch catalog models: #{e.class}: #{e.message}")
        []
      end
      decision_catalog_models = begin
        Llm::OpenRouterModelsService.decision_models
      rescue => e
        Rails.logger.warn("Admin::LlmSettingsController show_props failed to fetch decision catalog models: #{e.class}: #{e.message}")
        []
      end
      labels = build_catalog_labels(catalog_models, decision_catalog_models)
      options = serialized_model_options_payload(
        setting,
        catalog_models: catalog_models,
        decision_catalog_models: decision_catalog_models,
        labels: labels
      )

      {
        supported_models: options[:supported_models],
        supported_decision_models: options[:supported_decision_models],
        supported_extraction_models: options[:supported_extraction_models],
        available_openrouter_models: available_openrouter_models(
          setting,
          catalog_models: catalog_models,
          decision_catalog_models: decision_catalog_models,
          labels: labels
        ),
        # @lat: [[admin-llm-settings-controller-design#LlmSettings.tsx, the frontend page]]
        current_summarization_model: setting.summarization_model,
        current_classification_model: setting.classification_model,
        current_decision_model: setting.decision_model,
        current_extraction_model: setting.extraction_model,
        current_summarization_reasoning_effort: setting.summarization_reasoning_effort,
        current_classification_reasoning_effort: setting.classification_reasoning_effort,
        # @lat: [[llm-summaries#Batch summarisation#Why the batch path is off until it is switched on]]
        current_summary_batch_enabled: setting.summary_batch_enabled,
        updated_by: updated_by_user.nil? ? nil : {name: provenance_display_name(updated_by_user)},
        updated_at: setting.updated_at.iso8601
      }
    end

    def offered_models
      AdminSetting.offered_models
    end

    def offered_models_list(setting, catalog_models: nil, decision_catalog_models: nil)
      if decision_catalog_models
        catalog = catalog_models || []
        d_catalog = decision_catalog_models
        excluded = (
          AdminSetting::SUPPORTED_DECISION_MODELS +
          AdminSetting::SUPPORTED_EXTRACTION_MODELS +
          Llm::ModelCatalog::OPENROUTER_DECISION_ROUTES.keys +
          Llm::ModelCatalog::OPENROUTER_EXTRACTION_ROUTES.keys
        ).uniq

        raw_list = setting.offered_models
        raw_list = raw_list.map(&:to_s).map(&:strip).compact_blank.uniq if raw_list.is_a?(Array)
        raw_list = AdminSetting::SUPPORTED_MODELS.dup if raw_list.blank?

        filtered = raw_list.reject do |id|
          excluded.include?(id) || (
            !Llm::OpenRouterModelsService.lookup_decision_model(id, models: d_catalog).nil? &&
            Llm::OpenRouterModelsService.lookup(id, models: catalog).nil?
          )
        end

        filtered.presence || AdminSetting::SUPPORTED_MODELS.dup
      else
        setting.offered_models_list
      end
    end

    def offered_extraction_models_list(setting, catalog_models: nil, decision_catalog_models: nil)
      if decision_catalog_models
        raw_list = setting.offered_models
        raw_list = raw_list.map(&:to_s).map(&:strip).compact_blank.uniq if raw_list.is_a?(Array)
        raw_list = AdminSetting::SUPPORTED_MODELS.dup if raw_list.blank?

        (
          AdminSetting::SUPPORTED_EXTRACTION_MODELS +
          offered_models_list(setting, catalog_models: catalog_models, decision_catalog_models: decision_catalog_models) +
          raw_list.select { |id| Llm::ModelCatalog::OPENROUTER_EXTRACTION_ROUTES.key?(id) }
        ).uniq
      else
        setting.offered_extraction_models_list
      end
    end

    def build_catalog_labels(catalog_models, decision_catalog_models)
      labels = {}.merge(AdminSetting::SUPPORTED_MODEL_LABELS)
        .merge(AdminSetting::SUPPORTED_DECISION_MODEL_LABELS)
        .merge(AdminSetting::SUPPORTED_EXTRACTION_MODEL_LABELS)
        .merge(SUPPORTED_MODEL_LABELS)

      catalog_models.each do |m|
        labels[m[:id]] = m[:label] if m[:id].present? && m[:label].present?
      end

      decision_catalog_models.each do |m|
        labels[m[:id]] = m[:label] if m[:id].present? && m[:label].present?
      end

      labels
    end

    # @lat: [[admin-llm-settings-controller-design#Specialized decision and extraction model props and options]]
    def serialized_model_options_payload(setting, catalog_models: nil, decision_catalog_models: nil, labels: nil)
      catalog = catalog_models || begin
        Llm::OpenRouterModelsService.call
      rescue => e
        Rails.logger.warn("Admin::LlmSettingsController serialized_model_options_payload failed to fetch catalog models: #{e.class}: #{e.message}")
        []
      end
      d_catalog = decision_catalog_models || begin
        Llm::OpenRouterModelsService.decision_models
      rescue => e
        Rails.logger.warn("Admin::LlmSettingsController serialized_model_options_payload failed to fetch decision catalog models: #{e.class}: #{e.message}")
        []
      end
      resolved_labels = labels || build_catalog_labels(catalog, d_catalog)

      {
        supported_models: model_options(
          setting,
          catalog_models: catalog,
          decision_catalog_models: d_catalog,
          labels: resolved_labels
        ),
        supported_decision_models: decision_model_options(
          setting,
          decision_catalog_models: d_catalog,
          labels: resolved_labels
        ),
        supported_extraction_models: extraction_model_options(
          setting,
          catalog_models: catalog,
          decision_catalog_models: d_catalog,
          labels: resolved_labels
        )
      }
    end

    def label_for_model(id, catalog_models: nil, decision_catalog_models: nil, labels: nil)
      SUPPORTED_MODEL_LABELS.fetch(id) do
        resolved_labels = labels || build_catalog_labels(catalog_models || [], decision_catalog_models || [])
        resolved_labels[id] || id
      end
    end

    def available_openrouter_models(setting, catalog_models: nil, decision_catalog_models: nil, labels: nil)
      catalog = catalog_models || begin
        Llm::OpenRouterModelsService.call
      rescue => e
        Rails.logger.warn("Admin::LlmSettingsController available_openrouter_models failed: #{e.class}: #{e.message}")
        []
      end
      d_catalog = decision_catalog_models || begin
        Llm::OpenRouterModelsService.decision_models
      rescue => e
        Rails.logger.warn("Admin::LlmSettingsController available_openrouter_models failed to fetch decision models: #{e.class}: #{e.message}")
        []
      end
      resolved_labels = labels || build_catalog_labels(catalog, d_catalog)

      offered_models = offered_models_list(setting, catalog_models: catalog, decision_catalog_models: d_catalog)
      offered_entries = (
        offered_models +
        setting.offered_decision_models_list(decision_catalog_models: d_catalog) +
        offered_extraction_models_list(setting, catalog_models: catalog, decision_catalog_models: d_catalog)
      ).uniq

      offered_ids = (
        offered_entries +
        offered_entries.filter_map { |id| Llm::ModelCatalog.lookup(id, catalog_models: catalog)&.api_model }
      ).to_set

      candidates = []
      seen_ids = Set.new

      (AdminSetting::SUPPORTED_MODELS - offered_models).each do |id|
        seen_ids.add(id)
        candidates << {
          id: id,
          label: label_for_model(id, catalog_models: catalog, decision_catalog_models: d_catalog, labels: resolved_labels),
          supports_reasoning: Llm::ModelCatalog.supports_reasoning?(id, catalog_models: catalog)
        }
      end

      catalog.each do |model|
        id = model[:id]
        next if id.blank? || offered_ids.include?(id) || seen_ids.include?(id)

        seen_ids.add(id)
        candidates << {
          id: id,
          label: model[:label].presence || id,
          supports_reasoning: model.key?(:supports_reasoning) ? model[:supports_reasoning] : Llm::ModelCatalog.supports_reasoning?(id, catalog_models: catalog)
        }
      end

      d_catalog.each do |model|
        id = model[:id]
        next if id.blank? || offered_ids.include?(id) || seen_ids.include?(id)

        seen_ids.add(id)
        candidates << {
          id: id,
          label: model[:label].presence || id,
          supports_reasoning: false
        }
      end

      candidates.sort_by { |m| [m[:label].downcase, m[:id]] }
    end

    # @lat: [[admin-setting-model-list#Why the retired-model tests write the column directly]]
    # @lat: [[admin-llm-settings-controller-design#Query deduplication and label pre-resolution in model helpers]]
    def model_options(setting, catalog_models: nil, decision_catalog_models: nil, labels: nil)
      catalog = catalog_models || begin
        Llm::OpenRouterModelsService.call
      rescue => e
        Rails.logger.warn("Admin::LlmSettingsController model_options failed: #{e.class}: #{e.message}")
        []
      end
      resolved_labels = labels || build_catalog_labels(catalog, decision_catalog_models || [])

      offered_list = offered_models_list(setting, catalog_models: catalog, decision_catalog_models: decision_catalog_models)
      offered = offered_list.map do |id|
        {
          id: id,
          label: label_for_model(id, catalog_models: catalog, decision_catalog_models: decision_catalog_models, labels: resolved_labels),
          selectable: true,
          supports_reasoning: Llm::ModelCatalog.supports_reasoning?(id, catalog_models: catalog)
        }
      end

      decision_offered = setting.offered_decision_models_list(decision_catalog_models: decision_catalog_models)
      active_decision_in_classification = setting.classification_model if decision_offered.include?(setting.classification_model)

      if active_decision_in_classification.present? && !offered_list.include?(active_decision_in_classification)
        offered << {
          id: active_decision_in_classification,
          label: label_for_model(active_decision_in_classification, catalog_models: catalog, decision_catalog_models: decision_catalog_models, labels: resolved_labels),
          selectable: true,
          supports_reasoning: false
        }
      end

      stored = [setting.summarization_model, setting.classification_model].compact.uniq
      eligible_active = offered_list + (active_decision_in_classification ? [active_decision_in_classification] : [])
      retired = (stored - eligible_active).map do |id|
        {
          id: id,
          label: "#{id} — no longer offered",
          selectable: false,
          supports_reasoning: Llm::ModelCatalog.supports_reasoning?(id, catalog_models: catalog)
        }
      end
      offered + retired
    end

    # @lat: [[admin-llm-settings-controller-design#Specialized decision and extraction model props and options]]
    def decision_model_options(setting, decision_catalog_models: nil, labels: nil)
      d_catalog = decision_catalog_models || begin
        Llm::OpenRouterModelsService.decision_models
      rescue => e
        Rails.logger.warn("Admin::LlmSettingsController decision_model_options failed: #{e.class}: #{e.message}")
        []
      end
      resolved_labels = labels || build_catalog_labels([], d_catalog)

      offered_list = setting.offered_decision_models_list(decision_catalog_models: d_catalog)
      offered = offered_list.map do |id|
        {
          id: id,
          label: label_for_model(id, decision_catalog_models: d_catalog, labels: resolved_labels),
          selectable: true,
          supports_reasoning: false
        }
      end

      stored = setting.decision_model.to_s.presence
      retired = if stored && !offered_list.include?(stored)
        [
          {
            id: stored,
            label: "#{stored} — no longer offered",
            selectable: false,
            supports_reasoning: false
          }
        ]
      else
        []
      end

      offered + retired
    end

    # @lat: [[admin-llm-settings-controller-design#Specialized decision and extraction model props and options]]
    def extraction_model_options(setting, catalog_models: nil, decision_catalog_models: nil, labels: nil)
      catalog = catalog_models || begin
        Llm::OpenRouterModelsService.call
      rescue => e
        Rails.logger.warn("Admin::LlmSettingsController extraction_model_options failed: #{e.class}: #{e.message}")
        []
      end
      d_catalog = decision_catalog_models || begin
        Llm::OpenRouterModelsService.decision_models
      rescue => e
        Rails.logger.warn("Admin::LlmSettingsController extraction_model_options failed to fetch decision catalog models: #{e.class}: #{e.message}")
        []
      end
      resolved_labels = labels || build_catalog_labels(catalog, d_catalog)

      offered_list = offered_extraction_models_list(setting, catalog_models: catalog, decision_catalog_models: d_catalog)
      offered = offered_list.map do |id|
        {
          id: id,
          label: label_for_model(id, catalog_models: catalog, decision_catalog_models: d_catalog, labels: resolved_labels),
          selectable: true,
          supports_reasoning: Llm::ModelCatalog.supports_reasoning?(id, catalog_models: catalog)
        }
      end

      stored = setting.extraction_model.to_s.presence
      retired = if stored && !offered_list.include?(stored)
        [
          {
            id: stored,
            label: "#{stored} — no longer offered",
            selectable: false,
            supports_reasoning: Llm::ModelCatalog.supports_reasoning?(stored, catalog_models: catalog)
          }
        ]
      else
        []
      end

      offered + retired
    end

    # @lat: [[admin-llm-settings-controller-design#Why the provenance display redacts the phone number]]
    def provenance_display_name(user)
      user.full_name.presence || "Admin (no name set)"
    end
  end
end
