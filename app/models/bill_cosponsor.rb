# typed: strict
# == Schema Information
#
# Table name: bill_cosponsors
#
#  id            :bigint           not null, primary key
#  legislator_id :bigint           not null
#  bill_id       :bigint           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class BillCosponsor < ApplicationRecord
  belongs_to :legislator
  belongs_to :bill
end
