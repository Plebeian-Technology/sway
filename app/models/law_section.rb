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
# @lat: [[legislation-pipeline#Law sections stay within their jurisdiction]]
class LawSection < ApplicationRecord
  belongs_to :sway_locale

  has_many :bill_amendment_operations,
    foreign_key: :target_law_section_id,
    inverse_of: :target_law_section,
    dependent: :nullify

  validates :key, presence: true, uniqueness: {scope: :sway_locale_id}
  validates :article, :section, :body, :source_path, presence: true

  scope :by_sway_locale, ->(sway_locale) { where(sway_locale: sway_locale) }
end
