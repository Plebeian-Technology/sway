# typed: strict
# == Schema Information
#
# Table name: bill_cosponsors
#
#  id            :integer          not null, primary key
#  legislator_id :integer          not null
#  bill_id       :integer          not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class BillCosponsor < ApplicationRecord
  belongs_to :legislator
  belongs_to :bill
end
