# frozen_string_literal: true

class SwayLocale
  # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]
  module TermRulesRegistry
    # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]
    CONGRESS_LOCALE_NAME = "congress-congress-united_states"

    DECLARATIONS = DocumentReader.all.to_h { |doc| [doc.name, doc.to_term_rules] }.freeze

    class << self
      def fetch(locale_name)
        if const_defined?(:DECLARATIONS, false) && (custom = const_get(:DECLARATIONS)).is_a?(Hash) && custom.key?(locale_name)
          return custom[locale_name]
        end

        doc = DocumentReader.find(locale_name)
        return doc.to_term_rules if doc

        raise TermRules::Undeclared,
          "SwayLocale #{locale_name.inspect} has no term rules. Add an entry to " \
          "SwayLocale::TermRulesRegistry::DECLARATIONS saying when its terms begin " \
          "and how long they run, with the law it comes from. Sway will not guess: " \
          "borrowing another jurisdiction's calendar puts every vote in the wrong term."
      end

      def declared?(locale_name)
        if const_defined?(:DECLARATIONS, false) && (custom = const_get(:DECLARATIONS)).is_a?(Hash) && custom.key?(locale_name)
          return true
        end

        DocumentReader.declared_locale_names.include?(locale_name)
      end

      def declared_locale_names
        names = DocumentReader.declared_locale_names
        if const_defined?(:DECLARATIONS, false) && (custom = const_get(:DECLARATIONS)).is_a?(Hash)
          (names + custom.keys).uniq
        else
          names
        end
      end
    end
  end
end
