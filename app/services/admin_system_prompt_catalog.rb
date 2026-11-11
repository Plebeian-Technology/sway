# frozen_string_literal: true

# @lat: [[admin-system-prompts-page#Reading the instructions Sway sends the model]]
class AdminSystemPromptCatalog
  ENTRIES = [
    {
      id: "bill_summary",
      label: "Bill summary",
      purpose: "Sent once per bill to produce the public summary and the section-by-section breakdown.",
      builder_name: "BillSummaryPromptBuilder",
      model_key: :summarization,
      per_sway_locale: true
    },
    {
      id: "bill_positions",
      label: "Organization positions",
      purpose: "Sent once per bill to draw organization positions out of the hearing testimony.",
      builder_name: "BillPositionsPromptBuilder",
      model_key: :summarization
    },
    {
      id: "bill_categories",
      label: "Bill categories",
      purpose: "Sent by the category backfill for a summarised bill that still carries no active category.",
      builder_name: "BillCategoryPromptBuilder",
      model_key: :summarization
    },
    {
      id: "testimony_classification",
      label: "Testimony attachment classification",
      purpose: "Sent per batch of hearing attachments to decide which of them are public testimony.",
      builder_name: "Testimony::ClassificationPromptBuilder",
      model_key: :classification
    },
    {
      id: "testimony_source_kind",
      label: "Testimony source kind",
      purpose: "Sent per batch of cleaned testimony letters to decide who each letter speaks for.",
      builder_name: "Testimony::SourceKindPromptBuilder",
      model_key: :classification
    }
  ].freeze

  MODEL_SETTING_LABELS = {
    summarization: "Summarization model",
    classification: "Testimony classification model"
  }.freeze

  # @lat: [[admin-system-prompts-page#What the page shows when the taxonomy is empty]]
  EMPTY_TAXONOMY_REASON =
    "No categorisation prompt is sent on this installation. There are no active categories to " \
    "choose from, so BackfillBillCategoriesJob stops before the call rather than asking the " \
    "model to invent category names. This prompt appears here once a category is active on the " \
    "Categories admin page."

  def initialize(llm_settings_path:)
    @llm_settings_path = llm_settings_path
  end

  def as_props
    {
      models: models,
      active_category_count: active_categories.length,
      llm_settings_path: llm_settings_path,
      prompts: ENTRIES.flat_map { |entry|
        if entry[:per_sway_locale]
          sway_locales.map { |locale| locale_entry_props(entry, locale) }
        else
          [entry_props(entry)]
        end
      }
    }
  end

  private

  attr_reader :llm_settings_path

  def entry_props(entry)
    reason = unavailable_reason_for(entry.fetch(:id))
    text = reason.nil? ? system_prompt_for(entry.fetch(:id)) : nil
    model_key = entry.fetch(:model_key)

    {
      id: entry.fetch(:id),
      label: entry.fetch(:label),
      purpose: entry.fetch(:purpose),
      builder: entry.fetch(:builder_name),
      model: models.fetch(model_key),
      model_setting_label: MODEL_SETTING_LABELS.fetch(model_key),
      system_prompt: text,
      character_count: text&.length,
      unavailable_reason: reason,
      sway_locale_name: nil
    }
  end

  def locale_entry_props(entry, locale)
    reason = unavailable_reason_for_locale(entry.fetch(:id), locale)
    text = reason.nil? ? system_prompt_for_locale(entry.fetch(:id), locale) : nil
    model_key = entry.fetch(:model_key)

    {
      id: "#{entry.fetch(:id)}_#{locale.name}",
      label: entry.fetch(:label),
      purpose: entry.fetch(:purpose),
      builder: entry.fetch(:builder_name),
      model: models.fetch(model_key),
      model_setting_label: MODEL_SETTING_LABELS.fetch(model_key),
      system_prompt: text,
      character_count: text&.length,
      unavailable_reason: reason,
      sway_locale_name: locale.name
    }
  end

  # @lat: [[admin-system-prompts-page#What the page shows when the taxonomy is empty]]
  def unavailable_reason_for(id)
    return nil unless id == "bill_categories"
    return nil unless active_categories.empty?

    EMPTY_TAXONOMY_REASON
  end

  # @lat: [[admin-system-prompts-page#What the page shows when a locale lacks summarization instructions]]
  def unavailable_reason_for_locale(id, locale)
    case id
    when "bill_summary"
      unless SwayLocale::JurisdictionRulesRegistry.declared?(locale.name)
        return "No summarization prompt is sent for #{locale.name}. There are no jurisdiction " \
               "rules declared for this locale in SwayLocale::JurisdictionRulesRegistry. " \
               "Add an entry to SwayLocale::JurisdictionRulesRegistry::DECLARATIONS to declare it."
      end

      if locale.llm_bill_summarization_instruction&.legislative_body_makeup.blank?
        "No summarization prompt is sent for #{locale.name}. There is no legislative body " \
        "description in llm_bill_summarization_instructions for this locale. Run " \
        "SeedLlmBillSummarizationInstruction to seed it."
      end
    end
  end

  def system_prompt_for(id)
    case id
    when "bill_summary"
      BillSummaryPromptBuilder.new(placeholder_bill, active_categories: active_categories).system_prompt
    when "bill_positions"
      BillPositionsPromptBuilder.new(placeholder_bill).system_prompt
    when "bill_categories"
      BillCategoryPromptBuilder.new(placeholder_bill, active_categories: active_categories).system_prompt
    when "testimony_classification"
      Testimony::ClassificationPromptBuilder.new([]).system_prompt
    when "testimony_source_kind"
      Testimony::SourceKindPromptBuilder.new([]).system_prompt
    else
      raise ArgumentError, "unknown system prompt id: #{id.inspect}"
    end
  end

  def system_prompt_for_locale(id, locale)
    case id
    when "bill_summary"
      BillSummaryPromptBuilder.new(
        placeholder_bill_for(locale),
        active_categories: active_categories
      ).system_prompt
    else
      raise ArgumentError, "unknown per-locale system prompt id: #{id.inspect}"
    end
  end

  def models
    @models ||= {
      summarization: setting.summarization_model,
      classification: setting.classification_model
    }
  end

  # @lat: [[admin-system-prompts-page#Why an unsaved placeholder bill is the right input]]
  def placeholder_bill
    @placeholder_bill ||= Bill.new
  end

  # @lat: [[admin-system-prompts-page#Why an unsaved placeholder bill is the right input]]
  def placeholder_bill_for(locale)
    Bill.new(sway_locale: locale)
  end

  # @lat: [[admin-system-prompts-page#Why the real active category list is used]]
  # @lat: [[admin-system-prompts-page#Why the query for active categories is spelled again here]]
  def active_categories
    @active_categories ||= Category.where(active: true).order(:name).to_a
  end

  # @lat: [[admin-locales-registration-visibility#Why admin authoring and prompt previews scope to declared locales]]
  def sway_locales
    @sway_locales ||= SwayLocale.order(:id).select(&:declared?).reject do |locale|
      rules = locale.declared_jurisdiction_rules&.law_rules
      (rules&.dig(:retrieval) || rules&.dig(:engine))&.to_s == "unavailable"
    end
  end

  def setting
    @setting ||= AdminSetting.singleton
  end
end
