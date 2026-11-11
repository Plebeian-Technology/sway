# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_amendment_operations
# Database name: primary
#
#  id                        :integer          not null, primary key
#  anchor_text               :text
#  char_end                  :integer          default(-1), not null
#  char_start                :integer          default(-1), not null
#  operation                 :integer          not null
#  ordinal                   :integer          not null
#  replacement_text          :text
#  source                    :integer          default("text_pattern"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  bill_id                   :integer          not null
#  bill_section_reference_id :integer
#  target_law_section_id     :integer
#
# Indexes
#
#  idx_bill_amendment_ops_on_bill_ordinal                        (bill_id,ordinal)
#  index_bill_amendment_operations_on_bill_id                    (bill_id)
#  index_bill_amendment_operations_on_bill_section_reference_id  (bill_section_reference_id)
#  index_bill_amendment_operations_on_target_law_section_id      (target_law_section_id)
#
# Foreign Keys
#
#  bill_id                    (bill_id => bills.id)
#  bill_section_reference_id  (bill_section_reference_id => bill_section_references.id)
#  target_law_section_id      (target_law_section_id => law_sections.id)
#
FactoryBot.define do
  factory :bill_amendment_operation do
    bill
    bill_section_reference { nil }
    target_law_section { nil }
    operation { :strike }
    source { :text_pattern }
    anchor_text { "is hereby repealed" }
    replacement_text { nil }
    char_start { 0 }
    char_end { 18 }
    sequence(:ordinal) { |n| n }
  end
end
