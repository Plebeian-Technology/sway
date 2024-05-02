# typed: strict

# == Schema Information
#
# Table name: bills
#
#  id                        :integer          not null, primary key
#  external_id               :string           not null
#  external_version          :string
#  title                     :string           not null
#  link                      :string
#  chamber                   :string           not null
#  introduced_date_time_utc  :datetime         not null
#  house_vote_date_time_utc  :datetime
#  senate_vote_date_time_utc :datetime
#  level                     :string           not null
#  category                  :string           not null
#  legislator_id             :integer          not null
#  sway_locale_id            :integer          not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#

class Bill < ApplicationRecord
  extend T::Sig

  belongs_to :legislator
  belongs_to :sway_locale

  has_many :bill_cosponsors

  has_one :bill_score

  has_one :vote, inverse_of: :bill

  has_many :legislator_votes, inverse_of: :bill

  # after_create :create_bill_score

  sig { returns(SwayLocale) }
  def sway_locale
    T.cast(super, SwayLocale)
  end

  # sig { returns(BillScore) }
  # def create_bill_score
  #   BillScore.create(bill: self)
  # end
end
