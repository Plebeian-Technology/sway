# frozen_string_literal: true

module Seats
  # @lat: [[representative-resolution#Occupancy interval]]
  class OverlapValidator
    class OverlapError < StandardError; end
    class InvalidIntervalError < StandardError; end

    class << self
      def validate_term!(term)
        Seat.transaction { validate_term_in_transaction!(term) }
      end

      def overlaps?(start_a, end_a, start_b, end_b)
        start_a < end_b && start_b < end_a
      end

      private

      def validate_term_in_transaction!(term)
        if term.seat_id.blank?
          raise UnresolvedSeatError, "Term #{term.id || "new"} has no persisted seat identity"
        end

        seat = Seat.find_by(id: term.seat_id)
        unless seat
          raise UnresolvedSeatError, "Term #{term.id || "new"} has no persisted seat identity"
        end
        seat.lock!
        unless seat.district_id == term.district_id
          raise UnresolvedSeatError, "Seat #{seat.seat_identifier} does not belong to term district #{term.district_id}"
        end
        district_locale_id = District.where(id: term.district_id).pick(:sway_locale_id)
        legislator_locale_id = Legislator.where(id: term.legislator_id).pick(:sway_locale_id)
        seat_locale_id = District.where(id: seat.district_id).pick(:sway_locale_id)
        unless district_locale_id == seat_locale_id && legislator_locale_id == seat_locale_id
          raise UnresolvedSeatError, "Seat #{seat.seat_identifier} does not belong to term's legislator locale"
        end

        term_start, term_end = interval_for(term)

        seat.legislator_terms.where.not(id: term.id).find_each do |other|
          other_start, other_end = interval_for(other)
          next unless overlaps?(term_start, term_end, other_start, other_end)

          raise OverlapError,
            "Seat #{seat.seat_identifier} cannot have overlapping occupants: " \
            "Term #{term.id || "new"} (#{term_start}..#{term_end}) conflicts with " \
            "Term #{other.id} (#{other_start}..#{other_end})"
        end
      end

      def interval_for(term)
        start_date = TermWindow.begins_on(term)
        end_date = TermWindow.ends_on(term)
        unless start_date < end_date
          raise InvalidIntervalError, "Term #{term.id || "new"} has an invalid seat interval: it must end after it begins"
        end

        [start_date, end_date]
      rescue SwayLocale::TermRules::Undeclared => error
        raise InvalidIntervalError, "Term #{term.id || "new"} has no declared calendar for seat occupancy: #{error.message}"
      end
    end
  end
end
