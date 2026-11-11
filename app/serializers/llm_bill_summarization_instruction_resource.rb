# frozen_string_literal: true

class LlmBillSummarizationInstructionResource < ApplicationResource
  attributes :id,
    :sway_locale_id,
    :news_media_website_urls,
    :legislative_body_makeup,
    :last_seeded_at,
    :updated_at
end
