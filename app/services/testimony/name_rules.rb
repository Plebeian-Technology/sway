# frozen_string_literal: true

module Testimony
  # @lat: [[testimony-attachment-rules#Testimony attachment rules#Filename rule boundaries]]
  module NameRules
    LABELS = %i[bill_text ambiguous_bill_text testimony procedural undecided].freeze #: Array[Testimony::NameRules::label]

    SEPARATORS = /[_.-]+/

    TESTIMONY_PATTERNS = [
      /\btestimony\b/,
      /\bpublic comment\b/,
      /\bcomment only\b/,
      /\boppos(e|es|ed|ing|ition)\b/,
      /\bsupports?\b/,
      /\bin favor\b/,
      /\bcommunity association\b/
    ].freeze

    BILL_TEXT_PATTERNS = [
      /~\s*\d+\s*(st|nd|rd|th)\b/,
      /\b\d+\s*(st|nd|rd|th)\s+readers?\b/,
      /\benrolled\b/,
      /\bengrossed\b/,
      /\breprint\b/
    ].freeze

    AMBIGUOUS_BILL_TEXT_PATTERNS = [
      /\breaders?\b/,
      /\bsigned\b(?!\s+(letter|testimony|statement|comment))/,
      /(?<!with )(?<!with the )(?<!as )\b(amendments?|amdts?)\b/,
      /\bord(inance)?\s*\d/
    ].freeze

    PROCEDURAL_PATTERNS = [
      /\bvoi?ting record\b/,
      /\battendance\b/,
      /\bnews ?paper\b/,
      /\bnotice\b/,
      /\bhearing pack\w*/,
      /\bsynopsis\b/,
      /\bpresentation\b/,
      /\bpower ?point\b/,
      /\btransmittal\b/,
      /\bmemo(randum)?\b/,
      /\bplat\b/,
      /\bmap\b/,
      /\bfloor plan\b/,
      /\bstatement of intent\b/,
      /\bnotes\b/, # also covers "hearing notes"
      /\bcase study\b/,
      /\bstamped\b/,
      /\brequest to return\b/
    ].freeze

    class << self
      def classify(name, sway_locale:)
        return :undecided unless classification_enabled?(sway_locale)

        normalized = normalize(name)
        return :undecided if normalized.empty?

        return :bill_text if BILL_TEXT_PATTERNS.any? { |pattern| pattern.match?(normalized) }

        testimony_hit = TESTIMONY_PATTERNS.any? { |pattern| pattern.match?(normalized) }
        if AMBIGUOUS_BILL_TEXT_PATTERNS.any? { |pattern| pattern.match?(normalized) }
          return testimony_hit ? :ambiguous_bill_text : :bill_text
        end

        return :testimony if testimony_hit
        return :procedural if PROCEDURAL_PATTERNS.any? { |pattern| pattern.match?(normalized) }

        :undecided
      end

      def classification_enabled?(sway_locale)
        rules = if sway_locale.is_a?(SwayLocale)
          sway_locale.jurisdiction_rules
        elsif sway_locale.respond_to?(:jurisdiction_rules)
          sway_locale.public_send(:jurisdiction_rules)
        else
          slug = sway_locale.to_s
          return false if slug.blank? || !SwayLocale::JurisdictionRulesRegistry.declared?(slug)

          SwayLocale::JurisdictionRulesRegistry.fetch(slug)
        end

        rules&.testimony_classification_enabled? == true
      rescue SwayLocale::JurisdictionRules::Undeclared
        false
      end

      private

      def normalize(name)
        Sway::Utf8.scrub(name)
          .downcase
          .sub(/\.(pdf|docx?|txt|jpe?g|png)\z/, "")
          .gsub(SEPARATORS, " ")
          .squeeze(" ")
          .strip
      end
    end
  end
end
