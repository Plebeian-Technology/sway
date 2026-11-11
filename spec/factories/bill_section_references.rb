# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_section_references
# Database name: primary
#
#  id            :integer          not null, primary key
#  anchor        :text
#  article       :string           not null
#  authoritative :boolean          default(FALSE), not null
#  fuzzy_score   :integer
#  key           :string           not null
#  ordinal       :integer          not null
#  resolution    :integer          default("unresolved"), not null
#  section       :string           not null
#  title         :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_id       :integer          not null
#
# Indexes
#
#  idx_bill_section_refs_on_bill_ordinal     (bill_id,ordinal)
#  idx_bill_section_refs_on_key              (key)
#  index_bill_section_references_on_bill_id  (bill_id)
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
FactoryBot.define do
  factory :bill_section_reference do
    bill
    sequence(:key) { |n| "art_#{n}__sec_#{n}" }
    article { "1" }
    section { "1" }
    title { nil }
    anchor { "§ 1-1" }
    resolution { :unresolved }
    fuzzy_score { nil }
    sequence(:ordinal) { |n| n }
  end
end
