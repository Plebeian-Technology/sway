# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#Roster evidence for observed departures]]
class RetireDepartedLegislatorsService
  # @lat: [[current-legislator-term#Which term a legislator is serving now#Departure safeguards]]
  UNREPLACED_DEPARTURE_FLOOR = 3
  UNREPLACED_DEPARTURE_SHARE = 0.05

  def initialize(sway_locale, seen_identity_values, unidentified_entries: [], observed_on: Date.current)
    @sway_locale = sway_locale
    @seen_identity_values = seen_identity_values.to_set
    @unidentified_entries = unidentified_entries.compact.to_set
    @observed_on = observed_on
  end

  def call
    return [] unless sway_locale.term_rules.roster_lists_only_current_legislators
    return [] unless every_entry_was_understood?
    return [] unless departures_are_believable?

    departed.each { |legislator| end_current_term!(legislator) }
    []
  end

  private

  attr_reader :sway_locale, :seen_identity_values, :unidentified_entries, :observed_on

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Departure safeguards]]
  def departed
    @departed ||=
      Legislator
        .where(sway_locale_id: sway_locale.id)
        .serving
        .includes(active_term: {district: :sway_locale})
        .reject { |legislator| accounted_for?(legislator) }
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Departure safeguards]]
  def accounted_for?(legislator)
    return true if seen_identity_values.include?(legislator.external_id)

    seat = LegislatorIdentity.seat_from(legislator.external_id)
    seat.present? && unidentified_entries.include?(seat)
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Departure safeguards]]
  def every_entry_was_understood?
    seats_serving = Legislator
      .where(sway_locale_id: sway_locale.id)
      .serving
      .filter_map { |legislator| LegislatorIdentity.seat_from(legislator.external_id) }
      .to_set

    unresolved = unidentified_entries.reject { |entry| seats_serving.include?(entry) }
    return true if unresolved.empty?

    refuse(
      "retire_departed_members.entries_not_understood",
      unresolved: unresolved.to_a,
      note: "nobody retired — the roster carried entries naming no person and no seat " \
            "anybody holds, so any of the people missing could be one of them"
    )
    false
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Departure safeguards]]
  def arrivals
    matched =
      Legislator.where(sway_locale_id: sway_locale.id, external_id: seen_identity_values.to_a).count
    seen_identity_values.size - matched
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Departure safeguards]]
  def unreplaced_limit
    serving_count = Legislator.where(sway_locale_id: sway_locale.id).serving.count
    [UNREPLACED_DEPARTURE_FLOOR, (serving_count * UNREPLACED_DEPARTURE_SHARE).floor].max
  end

  def departures_are_believable?
    limit = unreplaced_limit
    unreplaced = departed.size - arrivals
    return true if unreplaced <= limit

    refuse(
      "retire_departed_members.too_many_unreplaced",
      departed: departed.size,
      arrived: arrivals,
      limit: limit,
      note: "nobody retired — a roster losing this many people with no replacements " \
            "reads as a truncated fetch, not as a wave of resignations"
    )
    false
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Departure safeguards]]
  def refuse(event, **metadata)
    SwayLogging.warn(event, sway_locale: sway_locale.name, **metadata)
    Sentry.capture_message(
      "#{event} in #{sway_locale.name}: #{metadata.except(:note).inspect}",
      level: :warning
    )
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#Roster evidence for observed departures]]
  def end_current_term!(legislator)
    term = legislator.active_term
    return if term.nil?
    return if term.ended_on.present?

    SwayLogging.warn(
      "retire_departed_members.observed_departure",
      sway_locale: sway_locale.name,
      external_id: legislator.external_id,
      observed_on: observed_on.to_s,
      note: "departure date not written — missing official departure date evidence; absence does not establish departure"
    )
  end
end
