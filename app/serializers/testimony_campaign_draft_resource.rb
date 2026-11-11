# frozen_string_literal: true

# @lat: [[campaign-letter-disclosure#Why the letter text is a prop of its own]]
# @lat: [[bill-creator-positions-tab#Why testimony report resources expose raw counts and evidence without confidence scores]]
class TestimonyCampaignDraftResource < ApplicationResource
  # @lat: [[campaign-position-cards#The draft's content hash is its whole identity]]
  attribute :content_hash do |draft|
    draft["id"]
  end

  attribute :sender_count do |draft|
    draft["sender_count"]
  end

  attribute :letter_count do |draft|
    draft["letter_count"]
  end

  # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why a repeat letter is marked, not hidden]]
  # @lat: [[testimony-duplicate-letter-marking#A draft can now report fewer letters than CampaignDraftFinder::MIN_LETTERS_FOR_REUSE]]
  attribute :repeat_letter_count do |draft|
    draft["repeat_letter_count"]
  end

  attribute :added_words_characters do |draft|
    draft["added_words"].to_s.length
  end

  attribute :senders_added_words_left_out do |draft|
    draft["senders_added_words_left_out"]
  end

  # @lat: [[campaign-draft-rejection#The problem: a campaign draft has no row]]
  attribute :rejected do |draft|
    Array(params[:rejected_hashes]).include?(draft["id"])
  end

  # @lat: [[campaign-draft-rejection#Releasing drafts to individual letters]]
  attribute :marked_individual do |draft|
    Array(params[:individual_hashes]).include?(draft["id"])
  end

  attribute :domain do |draft|
    draft["dominant_domain"]
  end
end
