# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-letters#Extracting organization entities per letter]]
  class OrganizationEntityExtractor
    NAMEABLE_SOURCE_KINDS = %w[named_organization person_speaking_for_org public_body].freeze
    MAX_LETTER_CHARS = 6_000
    LETTER_HEAD_CHARS = 4_500
    LETTER_TAIL_CHARS = 1_500
    LETTER_WINDOW_NOTICE = "\n[...middle of letter omitted for length...]\n"
    EXTRACTION_ENTITIES = {
      "org_name" => "Canonical name of the organization, coalition, or public body authoring or represented by the testimony letter, or empty string if none.",
      "summary" => "One-sentence summary of the organization position and primary argument on the bill."
    }.freeze

    def self.build(llm: :default, purpose: :extraction)
      return new(llm: llm, purpose: purpose) unless llm == :default
      return new(llm: nil, purpose: purpose) if Rails.env.test?

      route = Llm::RouteResolver.resolve(purpose: purpose)
      new(llm: Llm::Client.build(provider: route.provider.to_s), route: route, purpose: purpose)
    rescue => e
      SwayLogging.warn(
        "organization_entity_extractor.adapter_unavailable",
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      new(llm: nil, purpose: purpose)
    end

    def initialize(llm: nil, enabled: nil, route: nil, purpose: :extraction)
      @llm = llm
      @route = route
      @purpose = purpose
      @enabled = enabled.nil? ? !llm.nil? : enabled
      @model_fallback_letters = 0
    end

    def call(text:, letters:)
      return [[], empty_counts] if letters.empty?

      full_text = text.to_s
      @model_fallback_letters = 0

      augmented = letters.map do |letter|
        is_repeat = letter["repeat"] == true || letter[:repeat] == true
        is_excluded = letter["excluded"] == true || letter[:excluded] == true
        source_kind = (letter["source_kind"] || letter[:source_kind]).to_s

        if is_repeat || is_excluded || !NAMEABLE_SOURCE_KINDS.include?(source_kind)
          next letter.merge("extracted_org" => nil)
        end

        unless enabled? && !llm.nil?
          next letter.merge("extracted_org" => fallback_extracted_org(letter))
        end

        raw_text = letter_text_for(full_text, letter)
        stripped = Testimony::ExtractedText.strip_recipient_headers(
          Testimony::ExtractedText.strip_envelope(raw_text.lstrip)
        ).strip

        clean_text = Llm::UntrustedTextBlock.neutralize(
          Llm::PromptLabel.collapse(Sway::Utf8.scrub(stripped))
        )

        if clean_text.strip.empty?
          @model_fallback_letters += 1
          next letter.merge("extracted_org" => fallback_extracted_org(letter))
        end

        adapter = llm
        if !adapter.respond_to?(:generate_entity_extraction) || adapter.is_a?(Llm::ClaudeAdapter) || adapter.is_a?(Llm::LlamacppAdapter)
          @model_fallback_letters += 1
          next letter.merge("extracted_org" => fallback_extracted_org(letter))
        end

        windowed_text = if clean_text.length > MAX_LETTER_CHARS
          clean_text[0, LETTER_HEAD_CHARS].to_s + LETTER_WINDOW_NOTICE + clean_text[-LETTER_TAIL_CHARS, LETTER_TAIL_CHARS].to_s
        else
          clean_text
        end

        extracted = extract_entities(adapter, windowed_text)
        if extracted
          letter.merge("extracted_org" => extracted)
        else
          @model_fallback_letters += 1
          letter.merge("extracted_org" => fallback_extracted_org(letter))
        end
      end

      extracted_count = augmented.count do |l|
        extracted_org = l["extracted_org"]
        extracted_org.is_a?(Hash) && extracted_org["org_name"].present?
      end

      [augmented, {
        "org_entity_extracted_letters" => extracted_count,
        "org_entity_extraction_fallbacks" => @model_fallback_letters
      }]
    end

    private

    attr_reader :llm

    def enabled?
      @enabled
    end

    def empty_counts
      {
        "org_entity_extracted_letters" => 0,
        "org_entity_extraction_fallbacks" => 0
      }
    end

    def letter_text_for(full_text, letter)
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

    def fallback_extracted_org(letter)
      source_evidence = letter["source_evidence"] || letter[:source_evidence]
      raw_name = source_evidence.is_a?(Hash) ? (source_evidence["org_name"] || source_evidence[:org_name]) : nil
      raw_name_str = raw_name.to_s.strip
      return nil if raw_name_str.empty?

      {
        "org_name" => raw_name_str,
        "summary" => nil
      }
    end

    def model_for(adapter)
      route = @route || Llm::RouteResolver.resolve(purpose: @purpose || :extraction)
      route.api_model
    end

    def extract_entities(adapter, windowed_text)
      return nil if adapter.is_a?(Llm::ClaudeAdapter) || adapter.is_a?(Llm::LlamacppAdapter)

      response = adapter.generate_entity_extraction(
        model: model_for(adapter),
        content: windowed_text,
        entities: EXTRACTION_ENTITIES
      )

      entities = if response.is_a?(Hash)
        nested = response["entities"] || response[:entities]
        nested.is_a?(Hash) ? nested : response
      else
        {}
      end

      org_name = (entities["org_name"] || entities[:org_name]).to_s.strip
      summary = (entities["summary"] || entities[:summary]).to_s.strip

      if org_name.present?
        {
          "org_name" => org_name,
          "summary" => summary.presence
        }
      else
        SwayLogging.warn(
          "organization_entity_extractor.llm_failure",
          error_class: "BlankOrgName",
          message: "Extraction returned non-hash or blank org_name"
        )
        nil
      end
    rescue => e
      SwayLogging.warn(
        "organization_entity_extractor.llm_failure",
        error_class: e.class.name,
        message: e.message.to_s[0, 300]
      )
      nil
    end
  end
end
