# == Schema Information
#
# Table name: votes
#
#  id                           :integer          not null, primary key
#  house_roll_call_vote_number  :integer
#  senate_roll_call_vote_number :integer
#  bill_id                      :integer          not null
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#
# typed: true

class Vote < ApplicationRecord
  extend T::Sig

  belongs_to :bill

  after_create :create_legislator_votes

  sig { void }
  def create_legislator_votes
    CongressLegislatorVoteUpdateService.new(bill.id).run
  end
end
