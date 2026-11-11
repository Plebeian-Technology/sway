# frozen_string_literal: true

# == Schema Information
#
# Table name: legislators
# Database name: primary
#
#  id             :integer          not null, primary key
#  email          :string
#  fax            :string
#  first_name     :string           not null
#  last_name      :string           not null
#  last_seeded_at :datetime
#  link           :string
#  party          :string           not null
#  phone          :string
#  photo_url      :string
#  twitter        :string
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  external_id    :string           not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_legislators_on_external_id                     (external_id)
#  index_legislators_on_sway_locale_id                  (sway_locale_id)
#  index_legislators_on_sway_locale_id_and_external_id  (sway_locale_id,external_id) UNIQUE
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
# @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
class Legislator < ApplicationRecord
  include MirrorsExternalAsset

  mirrors_external_asset(attachment_name: "photo", url_column: "photo_url")

  belongs_to :sway_locale

  has_many :legislator_terms, dependent: :destroy
  alias_method :terms, :legislator_terms

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
  has_many :legislator_identifiers, dependent: :destroy
  has_many :representative_reassignments, dependent: :nullify

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Active-term association and roster preloading]]
  has_one :active_term,
    -> { LegislatorTerm.current },
    class_name: "LegislatorTerm",
    inverse_of: :legislator

  has_one :district, through: :active_term
  delegate :title, to: :active_term, allow_nil: true

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Active-term association and roster preloading]]
  scope :with_active_term, -> { includes(district: :sway_locale) }

  # @lat: [[legislator-history-serialization#Why term history preloading eager loads nested score families]]
  scope :with_term_history, -> {
    includes(
      {active_term: {district: :sway_locale}},
      {district: :sway_locale},
      {photo_attachment: :blob},
      legislator_terms: [
        :seat,
        {district: :sway_locale},
        :legislator_district_scores,
        :legislator_locale_scores
      ]
    )
  }

  # @lat: [[current-legislator-term#Which term a legislator is serving now]]
  scope :serving, -> { where(id: LegislatorTerm.current.select(:legislator_id)) }

  has_many :historical_score_explanations

  has_many :bills, dependent: :restrict_with_exception # sponsor
  has_many :legislator_votes, dependent: :destroy
  before_destroy :destroy_historical_score_explanations
  has_one_attached :photo

  class << self
    def to_party_char_from_name(party)
      if party.blank? || party.length <= 1
        party
      else
        party[0]&.upcase || party
      end
    end
  end

  def full_name
    "#{first_name} #{last_name}"
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now]]
  def serving?
    active_term.present?
  end

  # @lat: [[scores-and-agreement#Scores and agreement#Every score is bound to a term]]
  def current_district_score
    active_term&.legislator_district_scores&.first
  end

  def at_large?
    return false if district.nil?

    district.name.remove_non_digits.to_i.zero?
  end

  delegate :congress?, to: :sway_locale

  def to_builder
    Jbuilder.new do |l|
      l.id id
      l.sway_locale_id sway_locale_id
      l.external_id external_id
      l.active serving?
      l.link link
      l.email email
      l.title title
      l.first_name first_name
      l.last_name last_name
      l.full_name "#{first_name} #{last_name}"
      l.phone phone
      l.fax fax
      l.party party
      # @lat: [[sway-google-cloud-storage#A mirrored photo keeps its source address]]
      l.photo_url MirroredAssetUrl.for(photo, fallback: photo_url)
      l.district district&.to_sway_json
      l.twitter twitter
    end
  end

  private

  def destroy_historical_score_explanations
    historical_score_explanations.destroy_all if HistoricalScoreExplanation.table_exists?
  end
end
