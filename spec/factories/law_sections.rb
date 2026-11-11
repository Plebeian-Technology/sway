# frozen_string_literal: true

# == Schema Information
#
# Table name: law_sections
# Database name: primary
#
#  id             :integer          not null, primary key
#  article        :string           not null
#  body           :text             not null
#  key            :string           not null
#  section        :string           not null
#  source_path    :string           not null
#  title          :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  idx_law_sections_on_locale_key        (sway_locale_id,key) UNIQUE
#  index_law_sections_on_sway_locale_id  (sway_locale_id)
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
FactoryBot.define do
  factory :law_section do
    sway_locale
    sequence(:key) { |n| "art_#{n}__sec_#{n}" }
    article { "1" }
    section { "1" }
    title { "Section title" }
    body { "Section body text." }
    source_path { "law-xml/charter/section.xml" }
  end
end
