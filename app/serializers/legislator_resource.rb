# frozen_string_literal: true

# @lat: [[legislator-resource-design#Why contact details are included in serialized payloads]]
class LegislatorResource < ApplicationResource
  attributes :id, :external_id, :link, :email, :first_name,
    :last_name, :phone, :fax, :party, :twitter

  # @lat: [[legislator-resource-design#Why photo_url preserves its wire key across asset mirroring]]
  attribute :photo_url do |legislator|
    MirroredAssetUrl.for(legislator.photo, fallback: legislator.photo_url)
  end

  attribute :active do |legislator|
    legislator.serving?
  end

  # @lat: [[legislator-resource-design#Why term toggle and history copy coordinates with display_term]]
  attribute :title do |legislator|
    display_term(legislator)&.title
  end

  attribute :term_start_year do |legislator|
    display_term(legislator)&.term_start_year
  end

  attribute :term_end_year do |legislator|
    display_term(legislator)&.term_end_year
  end

  # @lat: [[legislator-resource-design#Why term toggle and history copy coordinates with display_term]]
  attribute :began_on do |legislator|
    display_term(legislator)&.began_on&.iso8601
  end

  attribute :ended_on do |legislator|
    display_term(legislator)&.ended_on&.iso8601
  end

  attribute :sway_locale_id do |legislator|
    legislator.sway_locale_id
  end

  attribute :full_name do |legislator|
    "#{legislator.first_name} #{legislator.last_name}"
  end

  # @lat: [[current-legislator-term#Which term a payload describes]]
  attribute :district do |legislator|
    district = display_term(legislator)&.district
    district && DistrictResource.new(district).serializable_hash
  end

  # @lat: [[legislator-history-serialization#Why session label uses declared jurisdiction rules with year fallback]]
  attribute :terms do |legislator|
    LegislatorResource.terms_for(legislator, params)
  end

  # @lat: [[legislator-resource-design#Why term toggle and history copy coordinates with display_term]]
  def self.display_term(legislator)
    legislator.active_term || legislator.legislator_terms.max_by(&:term_start_year)
  end

  def self.terms_for(legislator, params = {})
    active_term = legislator.active_term
    active_term_id = params&.dig(:active_term_id) || active_term&.id
    user_scores = params&.dig(:user_legislator_term_scores)
    if user_scores.nil? && params&.dig(:user_legislator)
      user_scores = params[:user_legislator].user_legislator_term_scores.index_by(&:legislator_term_id)
    end
    user_scores ||= {}
    explanations = params&.dig(:historical_score_explanations)

    terms = legislator.legislator_terms.to_a.sort_by { |t| -t.term_start_year }
    effective_active_term_id = active_term_id || terms.first&.id

    terms.map do |term|
      is_executive = term.seat&.chamber == "Executive"
      is_active_or_display = effective_active_term_id.present? && term.id == effective_active_term_id

      district_row = term.legislator_district_scores.first
      district_score = district_row && UserLegislatorTermScoreResource.group_score([district_row])

      locale_row = term.legislator_locale_scores.first
      locale_score = locale_row && UserLegislatorTermScoreResource.group_score([locale_row])

      uts = user_scores[term.id]
      user_score =
        if uts
          total = uts.count_agreed + uts.count_disagreed + uts.count_no_legislator_vote + uts.count_legislator_abstained
          total.positive? ? UserLegislatorTermScoreResource.counters([uts]) : nil
        end

      correction_explanation =
        if explanations.present?
          # @type var exp: untyped
          exp =
            if explanations.is_a?(Hash)
              explanations[term.id] || (is_active_or_display ? explanations[term.legislator_id] : nil)
            elsif explanations.is_a?(Array)
              explanations.find { |e| e.score_type == "term_#{term.id}" && (e.legislator_id.nil? || e.legislator_id == term.legislator_id) } ||
                (is_active_or_display ? explanations.find { |e| !e.score_type.to_s.start_with?("term_") && (e.legislator_id.nil? || e.legislator_id == term.legislator_id) } : nil)
            end

          if exp
            {
              title: exp.title,
              body: exp.body,
              delta: exp&.delta,
              score_type: exp&.score_type
            }
          end
        end

      {
        id: term.id,
        session_label: session_label(term),
        term_start_year: term.term_start_year,
        term_end_year: term.term_end_year,
        began_on: term.began_on&.iso8601,
        ended_on: term.ended_on&.iso8601,
        district_name: term.district&.name,
        is_executive: is_executive,
        active: active_term_id ? term.id == active_term_id : false,
        district_score: district_score,
        locale_score: locale_score,
        user_score: user_score,
        correction_explanation: correction_explanation
      }
    end
  end

  def self.session_label(term)
    rules = term.district&.sway_locale&.declared_jurisdiction_rules
    return "#{term.term_start_year}–#{term.term_end_year}" if rules.nil?

    case rules.session_numbering
    when :congress_ordinal
      "#{congress_number(term.term_start_year).ordinalize} #{rules.chamber_label}"
    when :term_years
      "#{term.term_start_year}–#{term.term_end_year} #{rules.chamber_label}"
    else
      "#{term.term_start_year}–#{term.term_end_year}"
    end
  end

  def self.congress_number(term_start_year)
    ((term_start_year - 1789) / 2) + 1
  end

  private

  def display_term(legislator)
    cache = (@display_term_by_id ||= {})
    key = legislator.object_id
    return cache[key] if cache.key?(key)

    cache[key] = self.class.display_term(legislator)
  end
end
