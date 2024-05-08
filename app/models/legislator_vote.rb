# typed: strict

# == Schema Information
#
# Table name: legislator_votes
#
#  id            :integer          not null, primary key
#  legislator_id :integer          not null
#  bill_id       :integer          not null
#  support       :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#
class LegislatorVote < ApplicationRecord
  extend T::Sig

  belongs_to :legislator
  belongs_to :bill

  after_initialize :upcase_support

  validates_inclusion_of :support, in: %w[FOR AGAINST ABSTAIN]

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
    support == 'FOR'
  end

  sig { returns(T::Boolean) }
  def against?
    support == 'AGAINST'
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
end
