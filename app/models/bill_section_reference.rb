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
# @lat: [[legislation-pipeline#Parsed references are replaced together]]
class BillSectionReference < ApplicationRecord
  belongs_to :bill
  has_many :bill_amendment_operations, dependent: :destroy

  enum :resolution, {exact: 0, fuzzy: 1, unresolved: 2}

  validates :key, :article, :section, presence: true
  validates :ordinal,
    presence: true,
    numericality: {only_integer: true, greater_than_or_equal_to: 0}

  default_scope -> { order(:ordinal) }
  scope :authoritative, -> { where(authoritative: true) }
end
