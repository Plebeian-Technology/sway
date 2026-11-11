# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#The vote-entry roster is everyone who ever held the seat#Matching a name resolves against the roster of the vote's own day]]
class LegislatorRoster
  # @lat: [[congress-roll-calls#Why Senate roll-call matching uses surname and state with a title fallback]]
  SENATE_TITLE = "Sen."
  HOUSE_TITLE = "Rep."

  def initialize(sway_locale:, on:)
    @sway_locale = sway_locale
    @on = on.to_date
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#The vote-entry roster is everyone who ever held the seat#Matching a name resolves against the roster of the vote's own day]]
  def terms
    @terms ||= LegislatorTerm
      .where(legislator: Legislator.where(sway_locale: @sway_locale))
      .includes(:legislator, district: :sway_locale)
      .to_a
      .group_by(&:legislator_id)
      .filter_map { |_legislator_id, held|
        TermWindow.running_on(@on, held) #: LegislatorTerm?
      }
  end

  # @lat: [[congress-roll-calls#Why Senate roll-call matching uses surname and state with a title fallback]]
  def with_external_id(external_id)
    return nil if external_id.blank?

    terms.find { |term| term.legislator.external_id == external_id }
  end

  # @lat: [[congress-roll-calls#Why Senate roll-call matching uses surname and state with a title fallback]]
  def named(last_name, region_code)
    return [] if last_name.blank? || region_code.blank?

    wanted = last_name.to_s.strip.downcase
    state = region_code.to_s.strip.upcase
    terms.select do |term|
      term.legislator.last_name.to_s.strip.downcase == wanted &&
        term.district.region_code == state
    end
  end

  # @lat: [[current-legislator-term#Which term a legislator is serving now#The vote-entry roster is everyone who ever held the seat#Matching a name resolves against the roster of the vote's own day]]
  def senator_named(last_name, region_code)
    candidates = named(last_name, region_code).reject { |term| term.title == HOUSE_TITLE }
    # @lat: [[congress-roll-calls#Why Senate roll-call matching uses surname and state with a title fallback]]
    return candidates.first if candidates.size == 1

    seated = candidates.select { |term| term.title == SENATE_TITLE }
    (seated.size == 1) ? seated.first : nil
  end
end
