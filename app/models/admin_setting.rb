# frozen_string_literal: true

# == Schema Information
#
# Table name: admin_settings
# Database name: primary
#
#  id                              :integer          not null, primary key
#  classification_model            :string           default("claude-haiku-4-5-20251001"), not null
#  classification_reasoning_effort :string
#  decision_model                  :string           default("ScaleDown Classify Latest"), not null
#  extraction_model                :string           default("ScaleDown Extract Latest"), not null
#  offered_models                  :json
#  summarization_model             :string           not null
#  summarization_reasoning_effort  :string
#  summary_batch_chunk_size        :integer          default(25), not null
#  summary_batch_enabled           :boolean          default(FALSE), not null
#  created_at                      :datetime         not null
#  updated_at                      :datetime         not null
#  updated_by_id                   :integer
#
# Indexes
#
#  index_admin_settings_on_updated_by_id  (updated_by_id)
#
# Foreign Keys
#
#  updated_by_id  (updated_by_id => users.id)
#
# @lat: [[admin-setting-model-list#Why AdminSetting enforces its own one-row rule twice]]
class AdminSetting < ApplicationRecord
  # @lat: [[admin-setting-model-list#Frontend: ModelSelectField.tsx and supportedModel.ts]]
  SUPPORTED_MODELS = [
    "claude-haiku-5-5",
    "claude-sonnet-5-5",
    "claude-opus-5-5",
    "Opus Latest",
    "Sonnet Latest",
    "Haiku Latest",
    "Gemini Argon Latest",
    "Gemini Flash Latest",
    "GLM Latest",
    "Deepseek Pro Latest",
    "Deepseek Flash Latest",
    "OpenRouter Auto"
  ].freeze

  # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
  SUPPORTED_MODEL_LABELS = {
    "claude-haiku-5-5" => "Haiku 5.5",
    "claude-sonnet-5-5" => "Sonnet 5.5",
    "claude-opus-5-5" => "Opus 5.5",
    "Opus Latest" => "Opus Latest",
    "Sonnet Latest" => "Sonnet Latest",
    "Haiku Latest" => "Haiku Latest",
    "Gemini Argon Latest" => "Gemini Argon Latest",
    "Gemini Flash Latest" => "Gemini Flash Latest",
    "GLM Latest" => "GLM Latest",
    "Deepseek Pro Latest" => "Deepseek Pro Latest",
    "Deepseek Flash Latest" => "Deepseek Flash Latest",
    "OpenRouter Auto" => "OpenRouter Auto"
  }.freeze

  # @lat: [[admin-setting-model-list#Specialized decision and extraction models]]
  SUPPORTED_DECISION_MODELS = [
    "ScaleDown Classify Latest",
    "Jev Latest",
    "Perplexity Decider Latest",
    "Perplexity Decider Flash Latest"
  ].freeze

  SUPPORTED_DECISION_MODEL_LABELS = {
    "ScaleDown Classify Latest" => "ScaleDown Classify Latest",
    "Jev Latest" => "Jev Latest",
    "Perplexity Decider Latest" => "Perplexity Decider Latest",
    "Perplexity Decider Flash Latest" => "Perplexity Decider Flash Latest"
  }.freeze

  SUPPORTED_EXTRACTION_MODELS = [
    "ScaleDown Extract Latest"
  ].freeze

  SUPPORTED_EXTRACTION_MODEL_LABELS = {
    "ScaleDown Extract Latest" => "ScaleDown Extract Latest"
  }.freeze

  # @lat: [[llm-summaries#Batch summarisation#What decides how many batches a run submits]]
  SUMMARY_BATCH_CHUNK_SIZE_DEFAULT = 25

  REASONING_EFFORTS = %w[low medium high].freeze

  belongs_to :updated_by, class_name: "User", optional: true

  before_validation :normalize_reasoning_efforts

  validates :summarization_model, presence: true
  validates :classification_model, presence: true
  validates :decision_model, presence: true
  validates :extraction_model, presence: true

  validates :summarization_reasoning_effort,
    inclusion: {in: REASONING_EFFORTS},
    allow_nil: true

  validates :classification_reasoning_effort,
    inclusion: {in: REASONING_EFFORTS},
    allow_nil: true

  validates :summary_batch_chunk_size,
    numericality: {only_integer: true, greater_than: 0, less_than_or_equal_to: 100}

  # @lat: [[admin-setting-model-list#Why the inclusion validations are conditional]]
  validates :summarization_model,
    inclusion: {in: ->(record) { record.offered_models_list }},
    if: :summarization_model_changed?

  # @lat: [[admin-setting-model-list#Why the inclusion validations are conditional]]
  validates :classification_model,
    inclusion: {in: ->(record) { (record.offered_models_list + record.offered_decision_models_list).uniq }},
    if: :classification_model_changed?

  # @lat: [[admin-setting-model-list#Why the inclusion validations are conditional]]
  validates :decision_model,
    inclusion: {in: ->(record) { record.offered_decision_models_list }},
    if: :decision_model_changed?

  # @lat: [[admin-setting-model-list#Why the inclusion validations are conditional]]
  validates :extraction_model,
    inclusion: {in: ->(record) { record.offered_extraction_models_list }},
    if: :extraction_model_changed?

  # @lat: [[admin-setting-model-list#Why AdminSetting enforces its own one-row rule twice]]
  validate :enforce_singleton

  def self.singleton
    first_or_create!(
      summarization_model: SUPPORTED_MODELS.first,
      classification_model: SUPPORTED_MODELS.first,
      decision_model: SUPPORTED_DECISION_MODELS.first,
      extraction_model: SUPPORTED_EXTRACTION_MODELS.first
    )
  end

  def self.offered_models(catalog_models: nil, decision_catalog_models: nil)
    first&.offered_models_list(catalog_models: catalog_models, decision_catalog_models: decision_catalog_models) || SUPPORTED_MODELS.dup
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    SUPPORTED_MODELS.dup
  end

  def self.offered_decision_models(decision_catalog_models: nil)
    first&.offered_decision_models_list(decision_catalog_models: decision_catalog_models) || SUPPORTED_DECISION_MODELS.dup
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    SUPPORTED_DECISION_MODELS.dup
  end

  def self.offered_extraction_models(catalog_models: nil, decision_catalog_models: nil)
    first&.offered_extraction_models_list(catalog_models: catalog_models, decision_catalog_models: decision_catalog_models) || SUPPORTED_EXTRACTION_MODELS.dup
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    SUPPORTED_EXTRACTION_MODELS.dup
  end

  def self.offered_model_labels(
    catalog_models: nil,
    decision_catalog_models: nil,
    setting: nil,
    precomputed_offered_models: nil
  )
    cached_labels, models = begin
      c = catalog_models || Llm::OpenRouterModelsService.call
      [
        c.each_with_object({}) do |m, h|
          h[m[:id]] = m[:label] if m[:id].present? && m[:label].present?
        end,
        c
      ]
    rescue => e
      Rails.logger.warn("AdminSetting.offered_model_labels cache read failed: #{e.class}: #{e.message}")
      [{}, []]
    end

    decision_labels, d_models = begin
      d = decision_catalog_models || Llm::OpenRouterModelsService.decision_models
      [
        d.each_with_object({}) do |m, h|
          h[m[:id]] = m[:label] if m[:id].present? && m[:label].present?
        end,
        d
      ]
    rescue => e
      Rails.logger.warn("AdminSetting.offered_model_labels decision cache read failed: #{e.class}: #{e.message}")
      [{}, []]
    end

    labels = cached_labels
      .merge(decision_labels)
      .merge(SUPPORTED_MODEL_LABELS)
      .merge(SUPPORTED_DECISION_MODEL_LABELS)
      .merge(SUPPORTED_EXTRACTION_MODEL_LABELS)

    resolved_setting = setting || begin
      first
    rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
      nil
    end

    offered_base =
      precomputed_offered_models ||
      (resolved_setting ? resolved_setting.offered_models_list(catalog_models: models, decision_catalog_models: d_models) : SUPPORTED_MODELS.dup)
    offered_decision = resolved_setting ? resolved_setting.offered_decision_models_list(decision_catalog_models: d_models) : SUPPORTED_DECISION_MODELS.dup
    offered_extraction =
      if resolved_setting
        resolved_setting.offered_extraction_models_list(
          catalog_models: models,
          decision_catalog_models: d_models,
          precomputed_offered_models: offered_base
        )
      else
        SUPPORTED_EXTRACTION_MODELS.dup
      end

    (offered_base + offered_decision + offered_extraction).uniq.each do |id|
      labels[id] ||= id
    end
    labels
  end

  def self.stored_model?(model_id)
    normalized = model_id.to_s.strip
    return false if normalized.blank?

    offered_models.include?(normalized) ||
      offered_decision_models.include?(normalized) ||
      offered_extraction_models.include?(normalized) ||
      exists?(summarization_model: normalized) ||
      exists?(classification_model: normalized) ||
      exists?(decision_model: normalized) ||
      exists?(extraction_model: normalized)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    false
  end

  def stored_model?(model_id)
    normalized = model_id.to_s.strip
    return false if normalized.blank?

    raw_offered_models_list.include?(normalized) ||
      summarization_model == normalized ||
      classification_model == normalized ||
      decision_model == normalized ||
      extraction_model == normalized
  end

  # @lat: [[admin-setting-model-list#Single-pass offered decision and extraction models]]
  def offered_models_list(catalog_models: nil, decision_catalog_models: nil)
    excluded = (
      SUPPORTED_DECISION_MODELS +
      SUPPORTED_EXTRACTION_MODELS +
      Llm::ModelCatalog::OPENROUTER_DECISION_ROUTES.keys +
      Llm::ModelCatalog::OPENROUTER_EXTRACTION_ROUTES.keys
    ).uniq

    non_excluded = raw_offered_models_list.reject { |id| excluded.include?(id) }
    return SUPPORTED_MODELS.dup if non_excluded.empty?

    decision_entries = decision_catalog_models || Llm::OpenRouterModelsService.decision_models
    filtered = non_excluded.reject do |id|
      !Llm::OpenRouterModelsService.lookup_decision_model(id, models: decision_entries).nil? &&
        (catalog_models ? Llm::OpenRouterModelsService.lookup(id, models: catalog_models) : Llm::OpenRouterModelsService.lookup(id)).nil?
    end

    filtered.presence || SUPPORTED_MODELS.dup
  end

  # @lat: [[admin-setting-model-list#Single-pass offered decision and extraction models]]
  def offered_decision_models_list(decision_catalog_models: nil)
    decision_entries = decision_catalog_models || Llm::OpenRouterModelsService.decision_models
    dynamic_decisions = raw_offered_models_list.select do |id|
      Llm::ModelCatalog::OPENROUTER_DECISION_ROUTES.key?(id) ||
        !Llm::OpenRouterModelsService.lookup_decision_model(id, models: decision_entries).nil?
    end
    (SUPPORTED_DECISION_MODELS + dynamic_decisions).uniq
  end

  def offered_extraction_models_list(catalog_models: nil, decision_catalog_models: nil, precomputed_offered_models: nil)
    base_models = precomputed_offered_models || offered_models_list(
      catalog_models: catalog_models,
      decision_catalog_models: decision_catalog_models
    )
    (
      SUPPORTED_EXTRACTION_MODELS +
      base_models +
      raw_offered_models_list.select { |id| Llm::ModelCatalog::OPENROUTER_EXTRACTION_ROUTES.key?(id) }
    ).uniq
  end

  def add_offered_model!(model_id, updated_by: nil)
    normalized = model_id.to_s.strip
    is_supported = SUPPORTED_MODELS.include?(normalized) ||
      SUPPORTED_DECISION_MODELS.include?(normalized) ||
      SUPPORTED_EXTRACTION_MODELS.include?(normalized)
    is_openrouter = normalized.present? && (
      !Llm::OpenRouterModelsService.lookup(normalized).nil? ||
      !Llm::OpenRouterModelsService.lookup_decision_model(normalized).nil?
    )

    if normalized.blank? || (!is_supported && !is_openrouter)
      errors.add(:offered_models, "is not a recognized OpenRouter model")
      raise ActiveRecord::RecordInvalid.new(self)
    end

    with_lock do
      updated_list = (raw_offered_models_list + [normalized]).uniq
      update!(offered_models: updated_list, updated_by: updated_by)
    end
  end

  def remove_offered_model!(model_id, updated_by: nil)
    normalized = model_id.to_s.strip

    with_lock do
      if [summarization_model, classification_model, decision_model, extraction_model].include?(normalized)
        errors.add(:offered_models, "cannot remove a model that is currently active")
        raise ActiveRecord::RecordInvalid.new(self)
      end

      current = raw_offered_models_list
      if normalized.blank? || !current.include?(normalized)
        errors.add(:offered_models, "is not in the offered models list")
        raise ActiveRecord::RecordInvalid.new(self)
      end

      remaining = current - [normalized]
      if remaining.empty?
        errors.add(:offered_models, "cannot remove the last offered model")
        raise ActiveRecord::RecordInvalid.new(self)
      end

      update!(offered_models: remaining, updated_by: updated_by)
    end
  end

  private

  def raw_offered_models_list
    list = offered_models
    if list.is_a?(Array)
      normalized = list.map(&:to_s).map(&:strip).compact_blank.uniq
      return normalized if normalized.any?
    end

    SUPPORTED_MODELS.dup
  end

  def enforce_singleton
    return unless new_record?
    return unless self.class.exists?

    errors.add(:base, "AdminSetting is a singleton — there is already a row.")
  end

  # @lat: [[admin-setting-model-list#Clearing reasoning effort on non-reasoning models]]
  def normalize_reasoning_efforts
    self.summarization_reasoning_effort = summarization_reasoning_effort.to_s.strip.presence
    self.classification_reasoning_effort = classification_reasoning_effort.to_s.strip.presence

    if summarization_reasoning_effort.present? && summarization_model.present? && !supports_reasoning_for_model?(summarization_model)
      self.summarization_reasoning_effort = nil
    end
    if classification_reasoning_effort.present? && classification_model.present? && !supports_reasoning_for_model?(classification_model)
      self.classification_reasoning_effort = nil
    end
  end

  def supports_reasoning_for_model?(model_id)
    return false if Llm::ModelCatalog.decision_model?(model_id) ||
      Llm::ModelCatalog.extraction_model?(model_id) ||
      (self.class.column_names.include?("decision_model") && decision_model == model_id)

    return true if Llm::ModelCatalog.supports_reasoning?(model_id)

    Llm::OpenRouterModelsService.valid_slug?(model_id) && stored_model?(model_id) && Llm::OpenRouterModelsService.lookup(model_id).nil?
  end
end
