# frozen_string_literal: true

# @lat: [[law-section-upsert-key-collision#Why LawSectionUpsert detects cross-corpus key collisions]]
class FetchLawService
  class LawSectionUpsert
    # @lat: [[law-section-upsert-key-collision#The cost, and how LawSectionKeyCollisionError catches it]]
    class LawSectionKeyCollisionError < StandardError; end

    def self.call(sway_locale:, key:, article:, section:, title:, body:, source_path:)
      law_section = LawSection.find_or_initialize_by(sway_locale: sway_locale, key: key)

      # @lat: [[law-section-upsert-key-collision#The cost, and how LawSectionKeyCollisionError catches it]]
      if law_section.persisted?
        existing_corpus = law_section.source_path.to_s.split("/").first
        incoming_corpus = source_path.to_s.split("/").first
        if existing_corpus.present? && incoming_corpus.present? && existing_corpus != incoming_corpus
          raise LawSectionKeyCollisionError,
            "LawSection key #{key.inspect} collides across corpora in locale " \
            "#{sway_locale.id} (existing #{existing_corpus.inspect} vs incoming " \
            "#{incoming_corpus.inspect}); the corpus-agnostic key would overwrite " \
            "one corpus's section with the other's."
        end
      end

      law_section.assign_attributes(
        article: article,
        section: section,
        title: title,
        body: body,
        source_path: source_path
      )
      law_section.save!
      law_section
    end
  end
end
