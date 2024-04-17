# == Schema Information
#
# Table name: legislator_votes
#
#  id            :bigint           not null, primary key
#  legislator_id :bigint           not null
#  bill_id       :bigint           not null
#  support       :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class LegislatorVote < ApplicationRecord
  belongs_to :legislator
  belongs_to :bill
end
