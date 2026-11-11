# frozen_string_literal: true

# @lat: [[legislator-history-serialization#Legislator history serialization]]
class LegislatorHistoryResource < ApplicationResource
  attribute :sessions do |user|
    history_sessions(user)
  end

  attribute :legislative_sessions do |user|
    history_sessions(user)
  end

  def history_sessions(user)
    cache = (@history_sessions_by_user ||= {})
    return cache[user] if cache.key?(user)

    cache[user] = LegislatorHistoryResource.sessions_for(user, params[:sway_locale])
  end

  class << self
    def sessions_for(user, sway_locale)
      return [] unless user && sway_locale

      # @lat: [[legislator-history-serialization#Why active district ids are loaded once up front]]
      active_district_ids = user.user_districts.active.pluck(:district_id)

      # @lat: [[legislator-history-serialization#Why locale filtering uses the legislator sway locale column]]
      entries = user
        .user_legislators
        .where(active: false)
        .joins(:legislator)
        .where(legislators: {sway_locale_id: sway_locale.id})
        .includes(
          {user_legislator_term_scores: {legislator_term: {district: :sway_locale}}},
          # @lat: [[legislator-history-serialization#Why portrait attachments and blobs are eager loaded]]
          # @lat: [[legislator-history-serialization#Why database reads are bounded during history serialization]]
          legislator: [
            :active_term,
            {district: :sway_locale},
            {photo_attachment: :blob},
            {legislator_terms: [:seat, {district: :sway_locale}, :legislator_district_scores, :legislator_locale_scores]}
          ]
        )
        .filter_map { |user_legislator| entry_for(user_legislator, active_district_ids) }

      entries
        .group_by { |entry| entry[:_session_key] }
        .values
        .sort_by { |grouped| -grouped.first[:_term_start_year] }
        .map { |grouped|
          {
            session_label: grouped.first[:_session_label],
            legislative_session_label: grouped.first[:_session_label],
            entries: grouped.map { |entry| entry.except(:_session_key, :_session_label, :_term_start_year) }
          }
        }
    end

    private

    def entry_for(user_legislator, active_district_ids)
      term = term_for(user_legislator)
      return nil unless term

      score_row = user_legislator.user_legislator_term_scores.to_a.find { |uts| uts.legislator_term_id == term.id }

      {
        legislator: LegislatorResource.new(user_legislator.legislator).serializable_hash,
        term: LegislatorTermResource.new(term).serializable_hash,
        score: UserLegislatorTermScoreResource.counters(score_row ? [score_row] : []),
        ended_reason: ended_reason(active_district_ids, term),
        _session_key: [term.district.sway_locale_id, term.term_start_year, term.term_end_year],
        _session_label: session_label(term),
        _term_start_year: term.term_start_year
      }
    end

    # @lat: [[legislator-history-serialization#Why database reads are bounded during history serialization]]
    def term_for(user_legislator)
      legislator = user_legislator.legislator
      terms_by_id = legislator.legislator_terms.index_by(&:id)
      scored_term = user_legislator.user_legislator_term_scores.to_a
        .max_by { |uts| (terms_by_id[uts.legislator_term_id] || uts.legislator_term)&.term_start_year.to_i }
        &.then { |uts| terms_by_id[uts.legislator_term_id] || uts.legislator_term }

      scored_term || legislator.legislator_terms.max_by(&:term_start_year)
    end

    # @lat: [[legislator-history-serialization#Why ended reason requires no per-entry query]]
    def ended_reason(active_district_ids, term)
      return "district_changed" unless active_district_ids.include?(term.district_id)

      ends_on = term.ended_on
      ends_on ||= TermWindow.ends_on(term) if SwayLocale::TermRulesRegistry.declared?(term.sway_locale.name)

      (ends_on && ends_on <= Date.current) ? "term_ended" : "link_inactive"
    end

    # @lat: [[legislator-history-serialization#Why session label uses declared jurisdiction rules with year fallback]]
    def session_label(term)
      rules = term.district.sway_locale.declared_jurisdiction_rules
      return "#{term.term_start_year}–#{term.term_end_year}" if rules.nil?

      case rules.session_numbering
      when :congress_ordinal
        "#{congress_number(term.term_start_year).ordinalize} #{rules.chamber_label}"
      when :term_years
        "#{term.term_start_year}–#{term.term_end_year} #{rules.chamber_label}"
      else
        raise ArgumentError,
          "LegislatorHistoryResource cannot write a session label for " \
          "session_numbering #{rules.session_numbering.inspect}"
      end
    end

    def congress_number(term_start_year)
      ((term_start_year - 1789) / 2) + 1
    end
  end
end
