# frozen_string_literal: true

# == Schema Information
#
# Table name: roll_calls
# Database name: primary
#
#  id                           :integer          not null, primary key
#  house_roll_call_vote_number  :integer
#  senate_roll_call_vote_number :integer
#  created_at                   :datetime         not null
#  updated_at                   :datetime         not null
#  bill_id                      :integer          not null
#
# Indexes
#
#  index_roll_calls_on_bill_id  (bill_id)
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#

class RollCall < ApplicationRecord
  self.table_name = "roll_calls"
  belongs_to :bill

  after_create :create_legislator_votes

  def to_builder
    Jbuilder.new do |v|
      v.id id
      v.house_roll_call_vote_number house_roll_call_vote_number
      v.senate_roll_call_vote_number senate_roll_call_vote_number
    end
  end

  private

  # @lat: [[legislator-vote-sweep-design#Why Vote.after_create hands the fetch to a background job]]
  def create_legislator_votes
    LegislatorVoteFetchJob.perform_later(bill.id)
  end
end
