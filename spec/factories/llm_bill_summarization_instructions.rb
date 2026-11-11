# frozen_string_literal: true

# == Schema Information
#
# Table name: llm_bill_summarization_instructions
# Database name: primary
#
#  id                      :integer          not null, primary key
#  last_seeded_at          :datetime
#  legislative_body_makeup :text
#  news_media_website_urls :json             not null
#  worked_example          :text
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  sway_locale_id          :integer          not null
#
# Indexes
#
#  index_llm_bill_summarization_instructions_on_sway_locale_id  (sway_locale_id) UNIQUE
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
FactoryBot.define do
  factory :llm_bill_summarization_instruction do
    sway_locale
    legislative_body_makeup { "A 15-member legislative body governing the City of Baltimore." }
    news_media_website_urls { [] }
  end
end
