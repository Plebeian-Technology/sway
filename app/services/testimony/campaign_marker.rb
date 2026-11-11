# frozen_string_literal: true

module Testimony
  # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#How CampaignMarker marks singleton domain drafts and bounds added words]]
  class CampaignMarker
    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#How CampaignMarker marks singleton domain drafts and bounds added words]]
    MAX_CAMPAIGN_ADDED_CHARS = 40_000

    SINGLETON_ID_LENGTH = 16

    Result = Data.define(:letters, :campaign_drafts)

    class << self
      def call(drafts:, letters:)
        new(drafts: drafts, letters: letters).call
      end
    end

    def initialize(drafts:, letters:)
      @drafts = drafts
      @letters = letters
    end

    def call
      confirmed_domains = confirmed_domain_set

      campaign_draft_id_by_index = {}
      singleton_drafts = []

      @letters.each_with_index do |letter, index|
        next if letter["excluded"] == true

        existing = letter["campaign_draft_id"]
        if existing
          campaign_draft_id_by_index[index] = existing
          next
        end
        next if letter["excluded_from_drafts"]

        domain = letter["sender_domain"]
        next unless domain && confirmed_domains.include?(domain)

        singleton = build_singleton_draft(letter)
        singleton_drafts << singleton
        campaign_draft_id_by_index[index] = singleton["id"]
      end

      all_drafts = (@drafts + singleton_drafts).map { |draft| finalize_draft(draft) }

      augmented_letters = @letters.each_with_index.map do |letter, index|
        letter.merge(
          "campaign_draft_id" => campaign_draft_id_by_index[index],
          "campaign_origin" => campaign_draft_id_by_index.key?(index)
        )
      end

      Result.new(letters: augmented_letters, campaign_drafts: all_drafts)
    end

    private

    def confirmed_domain_set
      domains = @letters.reject { |letter| letter["excluded"] == true }.filter_map { |letter| letter["sender_domain"] }.uniq
      return {} if domains.empty?

      SendingServiceDomain
        .where(domain: domains, label: SendingServiceDomain::CONFIRMED)
        .pluck(:domain)
        .index_with { true }
    end

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#How CampaignMarker marks singleton domain drafts and bounds added words]]
    def build_singleton_draft(letter)
      seed = "#{letter["sender_domain"]}:#{letter["position"]}"
      {
        "id" => Digest::SHA256.hexdigest(seed)[0, SINGLETON_ID_LENGTH],
        "letter_positions" => [letter.fetch("position")]
      }
    end

    def letters_by_position
      @letters_by_position ||= @letters.index_by { |letter| letter["position"] }
    end

    def letters_for(draft)
      draft
        .fetch("letter_positions")
        .filter_map { |position| letters_by_position[position] }
        .reject { |letter| letter["excluded"] == true }
    end

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a repeat letter is marked, not hidden]]
    # @lat: [[testimony-duplicate-letter-marking#A draft can now report fewer letters than CampaignDraftFinder::MIN_LETTERS_FOR_REUSE]]
    def finalize_draft(draft)
      members = letters_for(draft)
      counted_members = members.reject { |letter| letter["repeat"] }
      addresses = counted_members.pluck("sender_address")
      known_senders = addresses.compact_blank.uniq
      anonymous_senders = addresses.count { |address| address.blank? }

      added_words, left_out = bounded_added_words(counted_members)

      draft.merge(
        "campaign_origin" => true,
        "sender_count" => known_senders.length + anonymous_senders,
        "letter_count" => counted_members.length,
        "repeat_letter_count" => members.length - counted_members.length,
        "added_words" => added_words,
        "senders_added_words_left_out" => left_out,
        "dominant_domain" => dominant_domain(counted_members)
      )
    end

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#How CampaignMarker marks singleton domain drafts and bounds added words]]
    def dominant_domain(members)
      domains = members.filter_map { |letter| letter["sender_domain"] }
      return nil if domains.empty?

      domains.tally.max_by { |_domain, count| count }&.first
    end

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#How CampaignMarker marks singleton domain drafts and bounds added words]]
    def bounded_added_words(members)
      ordered = members.sort_by { |letter| letter.fetch("position").to_i }

      kept = []
      total = 0
      left_out = 0
      bound_reached = false

      ordered.each do |letter|
        words = letter["added_words"].to_s #: String
        next if words.empty?

        if !bound_reached && total + words.length <= MAX_CAMPAIGN_ADDED_CHARS
          kept << words
          total += words.length
        else
          bound_reached = true
          left_out += 1
        end
      end

      [kept.join("\n\n"), left_out]
    end
  end
end
