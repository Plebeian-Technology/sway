# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: legislator_votes
#
#  id            :integer          not null, primary key
#  support       :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_id       :integer          not null
#  legislator_id :integer          not null
#
# Indexes
#
#  index_legislator_votes_on_bill_id        (bill_id)
#  index_legislator_votes_on_legislator_id  (legislator_id)
#
# Foreign Keys
#
#  bill_id        (bill_id => bills.id)
#  legislator_id  (legislator_id => legislators.id)
#
class LegislatorVote < ApplicationRecord
  extend T::Sig

  belongs_to :legislator
  belongs_to :bill

  after_initialize :transform_support_to_for_against_abstain, :upcase_support

  validates :support, inclusion: {in: %w[FOR AGAINST ABSTAIN]}

  sig { returns(Bill) }
  def bill
    T.cast(super, Bill)
  end

  sig { returns(Legislator) }
  def legislator
    T.cast(super, Legislator)
  end

  sig { returns(T::Boolean) }
  def for?
    support == "FOR"
  end

  sig { returns(T::Boolean) }
  def against?
    support == "AGAINST"
  end

  sig { returns(T::Boolean) }
  def abstain?
    support.present? && !%w[FOR AGAINST].include?(support)
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |lv|
      lv.id id
      lv.legislator_id legislator_id
      lv.bill_id bill_id
      lv.support support
    end
  end

  private

  sig { void }
  def upcase_support
    self.support = support.upcase.strip
  end

  sig { void }
  def transform_support_to_for_against_abstain
    s = support.downcase
    case s
    when "yea"
      self.support = "FOR"
    when "yes"
      self.support = "FOR"
    when "aye"
      self.support = "FOR"
    when "nay"
      self.support = "AGAINST"
    when "no"
      self.support = "AGAINST"
    when "not voting"
      self.support = "ABSTAIN"
    when "present"
      self.support = "ABSTAIN"
    else
      s
    end
  end
end
