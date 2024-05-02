# typed: strict

# == Schema Information
#
# Table name: user_votes
#
#  id         :integer          not null, primary key
#  user_id    :integer          not null
#  bill_id    :integer          not null
#  support    :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#
class UserVote < ApplicationRecord
  extend T::Sig

  belongs_to :user
  belongs_to :bill

  after_initialize :upcase_support
  after_create :update_scores

  validates_inclusion_of :support, in: %w[FOR AGAINST]

  sig { returns(Bill) }
  def bill
    T.cast(super, Bill)
  end

  sig { returns(User) }
  def user
    T.cast(super, User)
  end

  sig { returns(T::Boolean) }
  def for?
    support == 'FOR'
  end

  sig { returns(T::Boolean) }
  def against?
    support == 'AGAINST'
  end

  sig { params(legislator: Legislator).returns(T.nilable(LegislatorVote)) }
  def legislator_votes(legislator)
    bill.legislator_votes.find do |lv|
      lv if lv.legislator.eql?(legislator)
    end
  end

  private

  # Update BillScore, BillScoreDistrict and UserLegislatorScore
  sig { returns(T.untyped) }
  def update_scores
    # districts = bill.sway_locale.districts.filter_map do |d|
    #   d if user.districts(bill.sway_locale).include?(d)
    # end
  end

  sig { void }
  def upcase_support
    self.support = support.upcase.strip
  end
end
