# frozen_string_literal: true
# == Schema Information
#
# Table name: votes
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
#  index_votes_on_bill_id  (bill_id)
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#

class Vote < ApplicationRecord
  belongs_to :bill

  after_create :create_legislator_votes

  def bill
    super
  end

  def to_builder
    Jbuilder.new do |v|
      v.id id
      v.house_roll_call_vote_number house_roll_call_vote_number
      v.senate_roll_call_vote_number senate_roll_call_vote_number
    end
  end

  private

  def create_legislator_votes
    if bill.sway_locale.congress?
      CongressLegislatorVoteUpdateService.new(bill.id).run
    elsif bill.sway_locale.regional?
      OpenStatesLegislatorVoteUpdateService.new(bill.id).run
    end
  end
end
