# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: bill_cosponsors
#
#  id            :integer          not null, primary key
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_id       :integer          not null
#  legislator_id :integer          not null
#
# Indexes
#
#  index_bill_cosponsors_on_bill_id        (bill_id)
#  index_bill_cosponsors_on_legislator_id  (legislator_id)
#
# Foreign Keys
#
#  bill_id        (bill_id => bills.id)
#  legislator_id  (legislator_id => legislators.id)
#
class BillCosponsor < ApplicationRecord
  belongs_to :legislator
  belongs_to :bill
end
