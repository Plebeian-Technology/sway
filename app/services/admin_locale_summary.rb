# frozen_string_literal: true

class AdminLocaleSummary
  TIER_LABELS = {
    "city" => "City",
    "state" => "State",
    "congress" => "U.S. Congress"
  }.freeze

  def as_props
    {tiers: tiers}
  end

  private

  def tiers
    by_tier = SwayLocale.includes(:llm_bill_summarization_instruction).all.group_by(&:tier)

    TIER_LABELS.map do |key, label|
      {key: key, label: label, locales: rows_for(by_tier.fetch(key, []))}
    end
  end

  # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
  def rows_for(locales)
    locales
      .sort_by { |locale| [-counts.fetch(locale.id, 0), locale.to_select_option[:label]] }
      .map { |locale|
        instruction = locale.llm_bill_summarization_instruction
        {
          id: locale.id,
          label: locale.to_select_option[:label],
          user_count: counts.fetch(locale.id, 0),
          sample_street: locale.sample_street,
          sample_postal_code: locale.sample_postal_code,
          sample_latitude: locale.sample_latitude,
          sample_longitude: locale.sample_longitude,
          summarization_instruction: instruction ? LlmBillSummarizationInstructionResource.new(instruction).serializable_hash : nil,
          news_sources: configured_news_sources(locale, instruction)
        }
      }
  end

  def configured_news_sources(locale, instruction)
    doc = begin
      SwayLocale::DocumentReader.current_for(locale.name)
    rescue KeyError
      nil
    end

    if doc
      doc.news_sources
    elsif instruction
      instruction.news_sources
    else
      []
    end
  end

  def counts
    @counts ||= SwayLocaleUserCountsService.by_sway_locale_id
  end
end
