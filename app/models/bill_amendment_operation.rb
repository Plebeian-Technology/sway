# frozen_string_literal: true

# @lat: [[bill-amendment-operation-column-contract#Why enum :operation passes scopes: false]]
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
class BillAmendmentOperation < ApplicationRecord
  belongs_to :bill
  belongs_to :bill_section_reference, optional: true
  belongs_to :target_law_section, class_name: "LawSection", optional: true

  # @lat: [[bill-amendment-operation-column-contract#Why enum :operation passes scopes: false]]
  enum :operation, {strike: 0, insert: 1, replace: 2}, scopes: false
  enum :source, {text_pattern: 0, markup: 1}, default: :text_pattern

  validates :operation, :source, presence: true
  validates :ordinal,
    presence: true,
    numericality: {only_integer: true, greater_than_or_equal_to: 0}

  default_scope -> { order(:ordinal) }
end
