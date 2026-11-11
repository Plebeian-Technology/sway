# frozen_string_literal: true

# @lat: [[campaign-letter-disclosure#Why the letter text is a prop of its own]]
class TestimonyCampaignLettersResource < ApplicationResource
  attribute :content_hash do |draft|
    draft["id"]
  end

  # @lat: [[campaign-letter-disclosure#Why a repeat letter is marked, not hidden]]
  attribute :letters do |draft|
    full_text = params[:full_text].to_s
    letters_by_position = params[:letters_by_position] || {}

    draft.fetch("letter_positions", []).filter_map do |position|
      letter = letters_by_position[position]
      next if letter.nil?

      offset = letter.fetch("character_offset").to_i
      length = letter.fetch("characters").to_i
      {
        position: position,
        text: Testimony::ExtractedText.strip_recipient_headers(full_text[offset, length].to_s),
        sender_address: letter["sender_address"],
        sender_domain: letter["sender_domain"],
        repeat: !!letter["repeat"]
      }
    end
  end
end
