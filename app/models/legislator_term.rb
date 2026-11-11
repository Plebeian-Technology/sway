# frozen_string_literal: true

# == Schema Information
#
# Table name: legislator_terms
# Database name: primary
#
#  id              :integer          not null, primary key
#  began_on        :date
#  began_on_source :string
#  ended_on        :date
#  ended_on_source :string
#  term_end_year   :integer          not null
#  term_start_year :integer          not null
#  title           :string
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  district_id     :integer          not null
#  legislator_id   :integer          not null
#  seat_id         :integer
#
# Indexes
#
#  index_legislator_terms_on_district_id                        (district_id)
#  index_legislator_terms_on_legislator_id_and_term_start_year  (legislator_id,term_start_year) UNIQUE
#  index_legislator_terms_on_seat_id                            (seat_id)
#
# Foreign Keys
#
#  district_id    (district_id => districts.id)
#  legislator_id  (legislator_id => legislators.id)
#  seat_id        (seat_id => seats.id)
#

# @lat: [[current-legislator-term#Which term a legislator is serving now]]
class LegislatorTerm < ApplicationRecord
  belongs_to :legislator
  belongs_to :district
  belongs_to :seat, optional: true, inverse_of: :legislator_terms
  delegate :sway_locale, to: :district

  has_many :legislator_district_scores, dependent: :destroy
  has_many :legislator_locale_scores, dependent: :destroy

  validates :term_start_year, uniqueness: {scope: :legislator_id}
  validates :began_on_source, inclusion: {in: DateSource::ALL}, allow_nil: true
  validates :began_on_source, presence: true, if: -> { began_on.present? }
  validates :ended_on_source, inclusion: {in: DateSource::ALL}, allow_nil: true
  validates :ended_on_source, presence: true, if: -> { ended_on.present? }
  validate :reject_clearing_resolved_seat
  validate :seat_district_matches_term_district, if: -> { seat_id.present? }
  validate :seat_and_person_share_locale, if: -> { seat_id.present? }
  validate :reject_overlapping_seat_occupancy, if: -> { seat_id.present? }

  # @lat: [[current-legislator-term#Which term a legislator is serving now]]
  # @lat: [[current-legislator-term#Why the candidates are bounded in SQL first]]
  # @lat: [[current-legislator-term#A locale with no declared calendar is skipped, not refused]]
  scope :current, ->(date = Date.current) {
    target_date = (date.is_a?(String) ? Date.parse(date) : date.to_date).iso8601
    clause = sanitize_sql_array(["#{TermWindow.begins_on_sql} <= ? AND ? < #{TermWindow.ends_on_sql}", target_date, target_date])
    where(Arel.sql(clause))
  }

  class << self
    # @lat: [[current-legislator-term#Why the answer is worked out once per request]]
    def current_ids
      today = Date.current
      remembered = Current.current_legislator_term_ids
      return remembered[:ids] if remembered && remembered[:date] == today

      ids = unscoped.current(today).pluck(:id)
      Current.current_legislator_term_ids = {date: today, ids: ids}
      ids
    end

    def forget_current_ids
      Current.current_legislator_term_ids = nil
    end

    # @lat: [[current-legislator-term#Why narrowing by legislator has its own entry point]]
    def current_for(legislator_ids)
      where(legislator_id: legislator_ids).current
    end

    # @lat: [[current-legislator-term#Which term a legislator is serving now]]
    def covering(vote_date, legislator:)
      candidates = where(legislator_id: legislator.id).includes(district: :sway_locale).to_a
      term = TermWindow.covering(vote_date, candidates) #: LegislatorTerm?
      term = nil if term && TermWindow.ends_on(term) <= vote_date
      return term if term
      return nil if candidates.any?

      SwayLogging.warn(
        "legislator_term.covering.legislator_has_no_terms",
        legislator_id: legislator.id,
        vote_date: vote_date
      )
      nil
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now]]
  def current?
    self.class.current_for([legislator_id]).exists?(id)
  end

  def update_columns(attributes)
    guarded_seat_fields = %w[seat_id district_id legislator_id term_start_year term_end_year began_on ended_on]
    return super unless (attributes.keys.map(&:to_s) & guarded_seat_fields).any?

    if attributes.key?(:seat_id) || attributes.key?("seat_id")
      requested_seat_id = attributes[:seat_id] || attributes["seat_id"]
      if requested_seat_id.blank? && seat_id_in_database.present?
        raise Seats::UnresolvedSeatError, "A resolved term cannot be detached from its seat"
      end
    end

    ApplicationRecord.transaction(requires_new: true) do
      result = super
      Seats::OverlapValidator.validate_term!(self) if seat_id.present?
      result
    end
  end

  private

  # @lat: [[representative-resolution#Seat identity]]
  def seat_district_matches_term_district
    return if seat&.district_id == district_id

    errors.add(:seat, "must belong to the term's district")
  end

  def seat_and_person_share_locale
    return if seat&.sway_locale_id == legislator&.sway_locale_id && district&.sway_locale_id == legislator&.sway_locale_id

    errors.add(:seat, "must belong to the legislator's locale and district")
  end

  def reject_clearing_resolved_seat
    return unless persisted? && seat_id.blank? && seat_id_in_database.present?

    errors.add(:seat, "cannot be cleared after a seat is resolved")
  end

  def reject_overlapping_seat_occupancy
    Seats::OverlapValidator.validate_term!(self)
  rescue Seats::OverlapValidator::OverlapError,
    Seats::OverlapValidator::InvalidIntervalError,
    Seats::UnresolvedSeatError => error
    errors.add(:seat, error.message)
  end
end
