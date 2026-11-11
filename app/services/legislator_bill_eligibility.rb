# frozen_string_literal: true

# @lat: [[legislators-controller-design#Bill of the Month voting record lives on the detail payload#Term and chamber eligibility filter]]
class LegislatorBillEligibility
  TITLE_ALIASES = {"State Delegate" => "Delegate", "State Senator" => "Senator"}.freeze

  CHAMBER_BY_LABEL = {
    "executive" => :executive,
    CongressChamber::WHITE_HOUSE.downcase => :executive,
    CongressChamber::SENATE.downcase => :senate,
    "house" => :house,
    "house of representatives" => :house,
    "house of delegates" => :house,
    "city council" => :council,
    "council" => :council
  }.freeze

  def self.eligible?(legislator:, bill:, has_recorded_vote: false)
    new(legislator).eligible?(bill:, has_recorded_vote:)
  end

  def initialize(legislator)
    @eligible_terms = build_eligible_terms(legislator)
  end

  def eligible?(bill:, has_recorded_vote: false)
    return true if has_recorded_vote
    return false if @eligible_terms.empty?

    bill_chamber_dates(bill).any? do |target_chamber, relevant_date|
      term_running_on?(target_chamber, relevant_date)
    end
  end

  private

  def build_eligible_terms(legislator)
    legislator.legislator_terms.to_a.filter_map do |term|
      chamber = term_chamber(term)

      [chamber, TermWindow.begins_on(term)...TermWindow.ends_on(term)]
    rescue SwayLocale::TermRules::Undeclared
      nil
    end
  end

  def term_chamber(term)
    chamber_from_label(term.seat&.chamber) ||
      chamber_from_label(declared_seat_chamber(term)) ||
      executive_title_chamber(term)
  end

  def chamber_from_label(label)
    CHAMBER_BY_LABEL[label.to_s.strip.downcase]
  end

  def declared_seat_chamber(term)
    title = term.title
    return nil if title.blank?

    locale = term.district&.sway_locale
    return nil unless locale && SwayLocale::TermRulesRegistry.declared?(locale.name)

    locale.term_rules.seat_chambers[TITLE_ALIASES.fetch(title, title)]
  end

  def executive_title_chamber(term)
    (term.title == CongressChamber::PRESIDENT || term.title == "President") ? :executive : nil
  end

  def bill_chamber_dates(bill)
    fallback = fallback_date(bill)
    house_date = bill.house_vote_date_time_utc&.to_date
    senate_date = bill.senate_vote_date_time_utc&.to_date

    case bill.chamber.to_s.strip.downcase
    when "council"
      [[:council, bill.vote_date_time_utc&.to_date || fallback]]
    when "house"
      [[:house, house_date || fallback], [:senate, senate_date]]
    when "senate"
      [[:senate, senate_date || fallback], [:house, house_date]]
    when "both"
      if house_date || senate_date
        [[:house, house_date], [:senate, senate_date]]
      else
        [[:house, fallback], [:senate, fallback]]
      end
    else
      [[nil, bill.vote_date_time_utc&.to_date || fallback]]
    end
  end

  def fallback_date(bill)
    bill.introduced_date_time_utc&.to_date || bill.scheduled_release_date_utc
  end

  def term_running_on?(target_chamber, date)
    return false if date.nil?

    @eligible_terms.any? do |chamber, window|
      (target_chamber.nil? || chamber.nil? || chamber == :executive || chamber == target_chamber) && window.cover?(date)
    end
  end
end
