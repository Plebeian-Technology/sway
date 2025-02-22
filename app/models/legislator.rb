# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: legislators
#
#  id          :integer          not null, primary key
#  active      :boolean          not null
#  email       :string
#  fax         :string
#  first_name  :string           not null
#  last_name   :string           not null
#  link        :string
#  party       :string           not null
#  phone       :string
#  photo_url   :string
#  title       :string
#  twitter     :string
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  district_id :integer          not null
#  external_id :string           not null
#
# Indexes
#
#  index_legislators_on_district_id  (district_id)
#
# Foreign Keys
#
#  district_id  (district_id => districts.id)
#
class Legislator < ApplicationRecord
  extend T::Sig

  # use inverse_of to specify relationship
  # https://stackoverflow.com/a/59222913/6410635
  belongs_to :district, inverse_of: :legislators

  has_one :legislator_district_score, inverse_of: :legislator, dependent: :destroy

  has_many :bills, dependent: :restrict_with_exception # sponsor
  has_many :legislator_votes, dependent: :destroy

  PARTY_BY_CHAR = {
    R: "Republican",
    D: "Democrat",
    I: "Independent",
    U: "Unknown"
  }.freeze

  class << self
    extend T::Sig
    sig { params(party: String).returns(T.nilable(String)) }
    def to_party_name_from_char(party)
      if party.length > 1
        party
      else
        PARTY_BY_CHAR[party.upcase.to_sym]
      end
    end

    sig { params(party: String).returns(String) }
    def to_party_char_from_name(party)
      if party.blank? || party.length <= 1
        party
      else
        T.cast(party[0], String).upcase
      end
    end
  end

  sig { returns(String) }
  def full_name
    "#{first_name} #{last_name}"
  end

  sig { returns(SwayLocale) }
  def sway_locale
    @sway_locale ||= district.sway_locale
  end

  sig { returns(District) }
  def district
    T.cast(super, District)
  end

  sig { returns(LegislatorDistrictScore) }
  def legislator_district_score
    T.cast(super, LegislatorDistrictScore)
  end

  # The year the Legislator was elected
  sig { returns(Numeric) }
  def election_year
    if congress?
      (created_at.year % 2 > 0) ? created_at.year - 1 : created_at.year
    else
      external_id.split("-").last.to_i
    end
  end

  delegate :congress?, to: :sway_locale

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |l|
      l.id id
      l.sway_locale_id district.sway_locale.id
      l.external_id external_id
      l.active active
      l.link link
      l.email email
      l.title title
      l.first_name first_name
      l.last_name last_name
      l.full_name "#{first_name} #{last_name}"
      l.phone phone
      l.fax fax
      l.party party
      l.photo_url photo_url
      l.district district.to_sway_json
      l.twitter twitter
    end
  end

  sig { params(bill: Bill).returns(T.nilable(LegislatorVote)) }
  def vote(bill)
    legislator_votes.find do |lv|
      lv if lv.bill.eql?(bill)
    end
  end
end
