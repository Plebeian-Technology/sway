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
#  summary                   :text
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
  has_many :organization_bill_positions, inverse_of: :bill

  scope :of_the_week, -> { last }

  sig { returns(SwayLocale) }
  def sway_locale
    T.cast(super, SwayLocale)
  end

  sig { returns(Legislator) }
  def legislator
    T.cast(super, Legislator)
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |b|
      b.id id
      b.external_id external_id
      b.external_version external_version
      b.title title
      b.summary summary
      b.link link
      b.chamber chamber
      b.introduced_date_time_utc introduced_date_time_utc
      b.house_vote_date_time_utc house_vote_date_time_utc
      b.senate_vote_date_time_utc senate_vote_date_time_utc
      b.level level
      b.category category
      b.sponsor_external_id legislator.external_id
      b.legislator_id legislator_id
      b.sway_locale_id sway_locale_id
      b.created_at created_at
    end
  end
end
