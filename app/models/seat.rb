# frozen_string_literal: true

# == Schema Information
#
# Table name: seats
# Database name: primary
#
#  id              :integer          not null, primary key
#  chamber         :string           not null
#  seat_identifier :string           not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  district_id     :integer          not null
#
# Indexes
#
#  index_seats_on_district_id                      (district_id)
#  index_seats_on_district_id_and_seat_identifier  (district_id,seat_identifier) UNIQUE
#
# Foreign Keys
#
#  district_id  (district_id => districts.id)
#
# @lat: [[representative-resolution#Seat identity]]
class Seat < ApplicationRecord
  belongs_to :district, inverse_of: :seats
  has_many :legislator_terms, inverse_of: :seat, dependent: :restrict_with_exception

  delegate :sway_locale, :sway_locale_id, to: :district

  validates :seat_identifier, presence: true, uniqueness: {scope: :district_id}
  validates :title, presence: true
  validates :chamber, presence: true

  class << self
    def find_or_create_by_identity!(district:, office_identity:, title:, chamber:)
      raise ArgumentError, "office identity is required" if office_identity.blank?

      seat = find_by(district:, seat_identifier: office_identity)
      return create!(district:, seat_identifier: office_identity, title:, chamber:) unless seat

      unless seat.title == title && seat.chamber == chamber
        raise IdentityConflictError, "Office identity #{office_identity.inspect} has conflicting title or chamber metadata"
      end

      seat
    end
  end

  class IdentityConflictError < StandardError; end

  def current_terms(date = Date.current)
    legislator_terms.includes(:legislator).select do |term|
      TermWindow.begins_on(term) <= date && date < TermWindow.ends_on(term)
    end
  end

  def active_term(date = Date.current)
    terms = current_terms(date)
    return nil if terms.empty?
    raise Seats::OverlapValidator::OverlapError, "Seat #{seat_identifier} has multiple current occupants" if terms.length > 1

    terms.first
  end

  def current_occupant(date = Date.current)
    active_term(date)&.legislator
  end
end
