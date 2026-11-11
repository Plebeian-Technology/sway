# frozen_string_literal: true

require "digest"

module Testimony
  # @lat: [[testimony-letters#How CleanAndGroupService orders and threads the cleaning steps]]
  # @lat: [[distributed-testimony-pipeline#End-to-end distributed pipeline across stages]]
  class CleanAndGroupService
    ARTIFACT_VERSION = 1

    # @lat: [[testimony-letters#How CleanAndGroupService orders and threads the cleaning steps]]
    TRANSIENT_LETTER_KEYS = %w[added_words excluded_from_drafts].freeze

    # @lat: [[testimony-letters#How CleanAndGroupService orders and threads the cleaning steps]]
    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a repeat letter is marked, not hidden]]
    STEP_ORDER = %i[
      repair_characters remove_boilerplate split_into_letters read_senders
      mark_duplicate_letters group_by_reuse mark_campaign_origin write_domain_counts
      classify_source_kind classify_stance extract_organization_entities
    ].freeze

    class << self
      def call(bill:, bill_run: nil, run: nil, classifier: nil, stance_classifier: nil, entity_extractor: nil)
        new(
          bill: bill,
          bill_run: bill_run,
          run: run,
          classifier: classifier,
          stance_classifier: stance_classifier,
          entity_extractor: entity_extractor
        ).call
      end
    end

    # @lat: [[testimony-letters#How CleanAndGroupService orders and threads the cleaning steps]]
    def initialize(bill:, bill_run: nil, run: nil, classifier: nil, stance_classifier: nil, entity_extractor: nil)
      @bill = bill
      @bill_run = bill_run
      @run = run
      @classifier = classifier
      @stance_classifier = stance_classifier
      @entity_extractor = entity_extractor
    end

    def call
      provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
      @manual_stance_overrides = extract_manual_stance_overrides(provisioning.cleaned_testimony)
      raw_text = provisioning.extracted_testimony.to_s

      text = raw_text
      letters = []
      groups = []
      step_counts = {}
      STEP_ORDER.each do |step|
        text, letters, groups, counts = run_step(step, text, letters, groups)
        step_counts.merge!(counts)
      end

      cleaned_letters = apply_manual_stance_overrides(
        text,
        letters #: Array[Hash[String, untyped]]
      )
      step_counts.merge!(recompute_stance_counts(cleaned_letters))
      artifact = {
        "version" => ARTIFACT_VERSION,
        "text" => text,
        "counts" => step_counts.merge(
          "raw_chars" => raw_text.length,
          "cleaned_chars" => text.length
        ),
        "letters" => cleaned_letters.map { |letter| letter.except(*TRANSIENT_LETTER_KEYS) },
        "campaign_drafts" => groups
      }

      provisioning.update!(cleaned_testimony: artifact, cleaned_testimony_at: Time.current)
      artifact
    end

    private

    attr_reader :bill, :bill_run, :run

    # @lat: [[testimony-letters#How CleanAndGroupService orders and threads the cleaning steps]]
    def run_step(step, text, letters, groups)
      case step
      when :repair_characters then repair_characters(text, letters, groups)
      when :remove_boilerplate then remove_boilerplate(text, letters, groups)
      when :split_into_letters then split_into_letters(text, letters, groups)
      when :read_senders then read_senders(text, letters, groups)
      when :mark_duplicate_letters then mark_duplicate_letters(text, letters, groups)
      when :group_by_reuse then group_by_reuse(text, letters, groups)
      when :mark_campaign_origin then mark_campaign_origin(text, letters, groups)
      when :write_domain_counts then write_domain_counts(text, letters, groups)
      when :classify_source_kind then classify_source_kind(text, letters, groups)
      when :classify_stance then classify_stance(text, letters, groups)
      when :extract_organization_entities then extract_organization_entities(text, letters, groups)
      else raise ArgumentError, "unknown clean-testimony step: #{step}"
      end
    end

    def repair_characters(text, letters, groups)
      result = Testimony::CharacterRepair.call(text)
      [
        result.text,
        letters,
        groups,
        {
          "broken_words" => result.broken_words,
          "resolved_from_bundle" => result.resolved_from_bundle,
          "resolved_by_fallback" => result.resolved_by_fallback,
          "left_unresolved" => result.left_unresolved
        }
      ]
    end

    def remove_boilerplate(text, letters, groups)
      result = Testimony::BoilerplateRemover.call(text)
      [
        result.text,
        letters,
        groups,
        {
          "banner_occurrences" => result.occurrences,
          "banner_characters_removed" => result.characters_removed
        }
      ]
    end

    def split_into_letters(text, _letters, groups)
      entries = Testimony::LetterSplitter.call(text)
      [text, entries, groups, {"letter_count" => entries.length}]
    end

    # @lat: [[testimony-letters#How CleanAndGroupService orders and threads the cleaning steps]]
    def read_senders(text, entries, groups)
      letters = []
      letters_with_a_sender = 0
      domains = []

      entries.each do |entry|
        sender = Testimony::SenderReader.call(entry.text)
        letters << {
          "position" => entry.position,
          "character_offset" => entry.character_offset,
          "characters" => entry.text.length,
          "sender_address" => sender.address,
          "sender_domain" => sender.domain
        }
        letters_with_a_sender += 1 if sender.address.present?
        domains << sender.domain if sender.domain
      end

      letters = apply_manual_stance_overrides(text, letters)

      counts = {
        "letters_with_a_sender" => letters_with_a_sender,
        "distinct_sender_domains" => domains.uniq.length
      }

      [text, letters, groups, counts]
    end

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a repeat letter is marked, not hidden]]
    def mark_duplicate_letters(text, letters, groups)
      result = Testimony::DuplicateLetterMarker.call(text: text, letters: letters)
      counts = {"repeat_letters" => result.letters.count { |letter| letter["repeat"] }}
      [text, result.letters, groups, counts]
    end

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a public body's letter never joins a draft]]
    # @lat: [[testimony-letters#Attachment boundaries and the five-page constituent ceiling]]
    def group_by_reuse(text, letters, _groups)
      manually_excluded, active_letters = letters.partition { |letter| letter["excluded"] == true }
      public_bodies, non_public = active_letters.partition { |letter| public_body_letter?(text, letter) }
      eligible, overlong = non_public.partition { |letter| !overlong_letter?(text, letter) }
      excluded = manually_excluded + public_bodies + overlong
      result = Testimony::CampaignDraftFinder.call(text: text, letters: eligible)
      kept_out = excluded.map { |letter| letter.merge("campaign_draft_id" => nil, "added_words" => "", "excluded_from_drafts" => true) }
      merged = (result.letters + kept_out).sort_by { |letter| letter.fetch("position").to_i }
      [text, merged, result.campaign_drafts, {"public_body_letters_kept_out_of_drafts" => public_bodies.length}]
    end

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a public body's letter never joins a draft]]
    def public_body_letter?(text, letter)
      body = text[letter.fetch("character_offset").to_i, letter.fetch("characters").to_i].to_s
      Testimony::SourceKindRules.classify(body, sender_address: letter["sender_address"]).kind == :public_body
    end

    # @lat: [[testimony-letters#Attachment boundaries and the five-page constituent ceiling]]
    def overlong_letter?(text, letter)
      body = text[letter.fetch("character_offset").to_i, letter.fetch("characters").to_i].to_s
      Testimony::ExtractedText.over_constituent_page_limit?(body)
    end

    def mark_campaign_origin(text, letters, groups)
      result = Testimony::CampaignMarker.call(drafts: groups, letters: letters)

      counts = {
        "group_count" => result.campaign_drafts.length,
        "campaign_origin_letters" => result.letters.count { |letter| letter["campaign_origin"] },
        "added_words_characters" => result.campaign_drafts.sum { |group| group.fetch("added_words").to_s.length },
        "senders_added_words_left_out" => result.campaign_drafts.sum { |group| group.fetch("senders_added_words_left_out").to_i }
      }

      [text, result.letters, result.campaign_drafts, counts]
    end

    def write_domain_counts(text, letters, groups)
      Testimony::DomainCountsWriter.call(bill: bill, letters: letters)
      [text, letters, groups, {}]
    end

    def classify_source_kind(text, letters, groups)
      classifier = @classifier || Testimony::SourceKindClassifier.build(purpose: :decision)
      augmented_letters, counts = classifier.call(text: text, letters: letters)
      [text, augmented_letters, groups, counts]
    end

    def classify_stance(text, letters, groups)
      prefilled_letters = apply_manual_stance_overrides(text, letters)
      classifier = @stance_classifier || Testimony::StanceClassifier.build(purpose: :decision)
      augmented_letters, counts = classifier.call(text: text, letters: prefilled_letters, bill: bill)
      [text, augmented_letters, groups, counts]
    end

    def extract_manual_stance_overrides(cleaned_testimony)
      return {} unless cleaned_testimony.is_a?(Hash)

      prior_text = cleaned_testimony["text"].to_s
      prior_letters = cleaned_testimony["letters"]
      return {} unless prior_letters.is_a?(Array)

      overrides = {}
      digest_letters = {}
      prior_letters.each do |letter|
        next unless letter.is_a?(Hash)

        digest = letter_body_digest(prior_text, letter)
        next if digest.blank?

        (digest_letters[digest] ||= []) << letter
        is_excluded = letter["excluded"] == true
        next unless letter["stance_override"] == true || is_excluded

        stance = letter["stance"].to_s
        has_valid_stance = Testimony::StanceClassifier::STANCES.include?(stance)
        next unless is_excluded || has_valid_stance

        override_entry = {"stance_override" => true}
        override_entry["stance"] = stance if has_valid_stance
        override_entry["excluded"] = true if is_excluded

        sender = letter["sender_address"].to_s.strip
        if sender.present?
          overrides[[sender, digest]] = override_entry
        else
          overrides[digest] = override_entry
        end
      end

      digest_letters.each do |digest, group_letters|
        next if overrides.key?(digest)
        next unless group_letters.all? { |l| l["stance_override"] == true || l["excluded"] == true }

        entries = group_letters.filter_map do |l|
          is_excl = l["excluded"] == true
          s = l["stance"].to_s
          valid_s = Testimony::StanceClassifier::STANCES.include?(s)
          next unless is_excl || valid_s

          entry = {"stance_override" => true}
          entry["stance"] = s if valid_s
          entry["excluded"] = true if is_excl
          entry
        end.uniq
        overrides[digest] = entries.first if entries.length == 1
      end

      overrides
    end

    def current_manual_stance_overrides
      reloaded = bill.bill_llm_provisioning&.reload&.cleaned_testimony
      if reloaded.is_a?(Hash) && reloaded["letters"].is_a?(Array) && reloaded["letters"].any?
        extract_manual_stance_overrides(reloaded)
      else
        (@manual_stance_overrides || {}).dup
      end
    end

    def apply_manual_stance_overrides(text, letters)
      overrides = current_manual_stance_overrides
      return letters if overrides.blank?

      letters.map do |letter|
        digest = letter_body_digest(text, letter)
        next letter if digest.blank?

        sender = letter["sender_address"].to_s.strip
        override_val = if sender.present?
          overrides[[sender, digest]] || overrides[digest]
        else
          overrides[digest]
        end

        if override_val.is_a?(Hash)
          updated = letter.merge(override_val)
          updated.delete("excluded") unless override_val["excluded"] == true
          updated
        elsif override_val.is_a?(String)
          letter.merge("stance" => override_val, "stance_override" => true)
        else
          letter
        end
      end
    end

    def recompute_stance_counts(letters)
      active = letters.reject { |l| l["excluded"] == true }
      {
        "stance_support_count" => active.count { |l| l["stance"] == "support" },
        "stance_oppose_count" => active.count { |l| l["stance"] == "oppose" },
        "stance_neutral_count" => active.count { |l| l["stance"] != "support" && l["stance"] != "oppose" }
      }
    end

    def letter_body_digest(text, letter)
      offset = letter["character_offset"]
      length = letter["characters"]
      return nil unless offset.is_a?(Integer) && length.is_a?(Integer) && offset >= 0 && length > 0

      normalized = text[offset, length].to_s.strip.gsub(/\s+/, " ")
      return nil if normalized.empty?

      Digest::SHA256.hexdigest(normalized)
    end

    def extract_organization_entities(text, letters, groups)
      extractor = @entity_extractor || Testimony::OrganizationEntityExtractor.build(purpose: :extraction)
      augmented_letters, counts = extractor.call(text: text, letters: letters)
      [text, augmented_letters, groups, counts]
    end
  end
end
