# typed: strict
# == Schema Information
#
# Table name: legislator_votes
#
#  id            :integer          not null, primary key
#  legislator_id :integer          not null
#  bill_id       :integer          not null
#  support       :string
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class LegislatorVote < ApplicationRecord
  belongs_to :legislator
  belongs_to :bill
end
