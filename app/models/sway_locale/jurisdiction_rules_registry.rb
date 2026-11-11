# frozen_string_literal: true

class SwayLocale
  # @lat: [[jurisdiction-rules#Jurisdiction declarations]]
  module JurisdictionRulesRegistry
    DECLARATIONS = DocumentReader.all.to_h { |doc| [doc.name, doc.to_jurisdiction_rules] }.freeze

    class << self
      def fetch(locale_name)
        if const_defined?(:DECLARATIONS, false) && (custom = const_get(:DECLARATIONS)).is_a?(Hash) && custom.key?(locale_name)
          return custom[locale_name]
        end

        doc = DocumentReader.find(locale_name)
        return doc.to_jurisdiction_rules if doc

        raise JurisdictionRules::Undeclared,
          "SwayLocale #{locale_name.inspect} has no jurisdiction rules. Add an entry to " \
          "SwayLocale::JurisdictionRulesRegistry::DECLARATIONS saying where its roster and " \
          "its votes come from, and what its legislature is called. Sway will not guess: " \
          "reading another jurisdiction's Legistar puts another city's dates on these bills."
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
