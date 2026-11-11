# frozen_string_literal: true

# @lat: [[legislation-path-root-resolution#Test isolation]]
# @lat: [[legislation-path-segment-safety#Why the locale is a name, not an id]]
module Legislation
  module Paths
    # @lat: [[legislation-path-segment-safety#Segment validation]]
    EXTERNAL_ID_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]{0,63}\z/

    # @lat: [[legislation-path-segment-safety#Segment validation]]
    UNSAFE_EXTERNAL_ID_ECHO_LENGTH = 120

    # @lat: [[legislation-path-segment-safety#Segment validation]]
    # @lat: [[pipeline-unsafe-external-id-rescue#This one rescue covers every reachable raise]]
    class UnsafeExternalIdError < StandardError; end

    # @lat: [[legislation-path-segment-safety#Segment validation]]
    def self.external_id_segment!(value)
      segment = external_id_segment(value)
      return segment unless segment.nil?

      raise UnsafeExternalIdError,
        "Legislation::Paths: external_id #{value.to_s[0, UNSAFE_EXTERNAL_ID_ECHO_LENGTH].inspect} " \
        "is not usable as a path segment"
    end

    # @lat: [[legislation-path-segment-safety#Segment validation]]
    def self.external_id_segment(value)
      segment = value.to_s.strip
      segment if segment.match?(EXTERNAL_ID_PATTERN)
    end

    # @lat: [[legislation-path-segment-safety#Why the locale is a name, not an id]]
    def self.sway_locale_segment!(value)
      segment = sway_locale_segment(value)
      return segment unless segment.nil?

      raise UnsafeExternalIdError,
        "Legislation::Paths: sway_locale name #{value.to_s[0, UNSAFE_EXTERNAL_ID_ECHO_LENGTH].inspect} " \
        "is not usable as a path segment"
    end

    # @lat: [[legislation-path-segment-safety#Segment validation]]
    def self.sway_locale_segment(value)
      raw = value.is_a?(SwayLocale) ? value.name : value.to_s
      segment = raw.to_s.strip
      segment if segment.match?(EXTERNAL_ID_PATTERN)
    end

    # @lat: [[legislation-path-segment-safety#Segment validation]]
    def self.upstream_file_name(value)
      text = value.is_a?(::String) ? value : nil
      return nil if text.nil?

      cleaned = Sway::Utf8.scrub(text).delete("\0").strip
      return nil if cleaned.empty?

      name = File.basename(cleaned)
      return nil if name.empty? || name == "." || name == ".."

      name
    end

    # @lat: [[legislation-path-segment-safety#Segment validation]]
    def self.bill_artifact_dir(external_id, sway_locale:)
      bills_raw.join(sway_locale_segment!(sway_locale), external_id_segment!(external_id))
    end

    def self.bill_pdf_glob(external_id, sway_locale:)
      bill_artifact_dir(external_id, sway_locale: sway_locale).join("*.pdf").to_s
    end

    def self.bill_metadata_file(external_id, sway_locale:)
      bill_artifact_dir(external_id, sway_locale: sway_locale).join("metadata.json")
    end

    def self.bill_text_file(external_id, sway_locale:)
      bills_text.join(sway_locale_segment!(sway_locale), "#{external_id_segment!(external_id)}.md")
    end

    def self.hearings_file(external_id, sway_locale:)
      hearings.join(sway_locale_segment!(sway_locale), "#{external_id_segment!(external_id)}.json")
    end

    def self.diff_json_file(external_id, sway_locale:)
      diffs.join(sway_locale_segment!(sway_locale), "#{external_id_segment!(external_id)}.json")
    end

    def self.diff_markdown_file(external_id, sway_locale:)
      diffs.join(sway_locale_segment!(sway_locale), "#{external_id_segment!(external_id)}.md")
    end

    def self.prompt_dump_file(external_id, answer_type:, sway_locale:)
      raise ArgumentError, "answer_type must be present" if answer_type.to_s.strip.empty?

      prompt_dumps.join(sway_locale_segment!(sway_locale), external_id_segment!(external_id))
    end

    def self.attachment_dir(sway_locale:)
      attachments.join(sway_locale_segment!(sway_locale))
    end

    # @lat: [[legislation-path-root-resolution#Test isolation]]
    def self.root
      override = Sway::Settings.legislation.legislation_root.to_s
      return resolve(override) unless override.empty?

      isolated_root = Sway::LegislationTestIsolation.root_override
      return isolated_root if isolated_root

      Rails.root.join("legislation")
    end

    def self.bills_raw
      sub(:legislation_bills_raw_root, "bills/raw")
    end

    def self.bills_text
      sub(:legislation_bills_text_root, "bills/text")
    end

    def self.hearings
      sub(:legislation_hearings_root, "hearings")
    end

    # @lat: [[legislation-pipeline#Law artifact readiness]]
    def self.law(sway_locale: nil)
      base = sub(:legislation_law_root, "law")
      return base if sway_locale.nil?

      segment = sway_locale_segment!(sway_locale)
      scoped = base.join(segment)

      if legacy_path_fallback?(sway_locale) && !scoped.exist? && base.exist?
        return base
      end

      scoped
    end

    # @lat: [[legislation-pipeline#Law artifact readiness]]
    def self.law_section_index_file(sway_locale:)
      law(sway_locale: sway_locale).join("section_index.json")
    end

    def self.legacy_path_fallback?(sway_locale)
      rules = if sway_locale.is_a?(SwayLocale)
        sway_locale.jurisdiction_rules
      elsif sway_locale.respond_to?(:jurisdiction_rules)
        sway_locale.public_send(:jurisdiction_rules)
      else
        segment = sway_locale_segment(sway_locale)
        return false if segment.nil? || !SwayLocale::JurisdictionRulesRegistry.declared?(segment)

        SwayLocale::JurisdictionRulesRegistry.fetch(segment)
      end

      rules&.legacy_path_fallback? == true
    rescue SwayLocale::JurisdictionRules::Undeclared
      false
    end

    def self.diffs
      sub(:legislation_diffs_root, "diffs")
    end

    def self.prompt_dumps
      sub(:legislation_prompt_dumps_root, "prompt_dumps")
    end

    # @lat: [[legislation-path-root-resolution#Test isolation]]
    def self.attachments
      sub(:legislation_attachments_root, "attachments")
    end

    # @lat: [[legislation-path-root-resolution#Test isolation]]
    def self.sub(attribute, relative)
      override = Sway::Settings.legislation.public_send(attribute).to_s
      return root.join(relative) if override.empty?

      resolve(override)
    end

    # @lat: [[legislation-path-root-resolution#Test isolation]]
    def self.resolve(value)
      path = Pathname.new(value)
      path.absolute? ? path : Rails.root.join(value)
    end
  end
end
