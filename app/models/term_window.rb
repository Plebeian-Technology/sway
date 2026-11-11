# frozen_string_literal: true

# @lat: [[term-window-design#Why term_window_spec.rb tests against Struct stand-ins, not real LegislatorTerm records]]
class TermWindow
  class << self
    def convening_date(sway_locale, term_start_year)
      sway_locale.term_rules.convening.date_in(term_start_year)
    end

    # @lat: [[term-window-design#Why formatTermWindow (app/frontend/sway_utils/termWindow.ts) prefers the real day]]
    def begins_on(term)
      term.began_on || convening_date(term.sway_locale, term.term_start_year)
    end

    # @lat: [[term-window-design#Why covering checks starts alone]]
    def covering(vote_date, candidate_terms)
      candidate_terms
        .select { |term| begins_on(term) <= vote_date }
        .max_by { |term| begins_on(term) }
    end

    # @lat: [[retire-departed-members-safety-design#Why a stored term widens to hold a real end date, instead of narrowing#Why TermWindow.ends_on defaults to the successor's convening date]]
    def ends_on(term)
      term.ended_on || convening_date(term.sway_locale, term.term_end_year)
    end

    # @lat: [[legislator-term-current-and-covering#Why the departed-member fix uses running_on instead of covering]]
    def running_on(date, candidate_terms)
      candidate_terms
        .select { |term| begins_on(term) <= date }
        .select { |term| date < ends_on(term) }
        .max_by { |term| begins_on(term) }
    end

    # @lat: [[term-window-design#Why running_term_start_year counts forward, never backward]]
    def running_term_start_year(sway_locale, first_year, years_long, date = Date.current)
      date = date.to_date
      year = first_year
      year += years_long while convening_date(sway_locale, year + years_long) <= date
      year
    end

    # @lat: [[term-window-design#Why cycle_start_year walks from an anchor rather than sweeping candidates]]
    def cycle_start_year(sway_locale, date)
      date = date.to_date
      anchor, years = cycle_anchor_and_years(sway_locale)

      year = anchor + (((date.year - anchor) / years.to_f).floor * years).to_i
      year -= years while convening_date(sway_locale, year) > date
      year += years while convening_date(sway_locale, year + years) <= date
      year
    end

    # @lat: [[term-window-design#Why formatTermWindow (app/frontend/sway_utils/termWindow.ts) prefers the real day]]
    def cycle_ends_on(sway_locale, cycle_start_year)
      _anchor, years = cycle_anchor_and_years(sway_locale)
      convening_date(sway_locale, cycle_start_year + years)
    end

    # @lat: [[current-legislator-term#Which term a legislator is serving now#Declared calendars]]
    def convening_date_sql(year_column)
      locale_subquery = <<~SQL.squish
        (SELECT LOWER(sway_locales.city) || '-' || LOWER(sway_locales.region_name)
         FROM districts
         INNER JOIN sway_locales ON sway_locales.id = districts.sway_locale_id
         WHERE districts.id = legislator_terms.district_id)
      SQL

      cases = SwayLocale::TermRulesRegistry::DECLARATIONS.map do |locale_name, rules|
        city, region, _country = locale_name.split("-")
        rule_sql = rules.convening.sql_date_expr(year_column)
        "WHEN '#{city}-#{region}' THEN #{rule_sql}"
      end.join(" ")

      "CASE #{locale_subquery} #{cases} ELSE NULL END"
    end

    # @lat: [[term-window-design#Why formatTermWindow (app/frontend/sway_utils/termWindow.ts) prefers the real day]]
    def begins_on_sql(year_column = "legislator_terms.term_start_year", began_on_column = "legislator_terms.began_on")
      "COALESCE(#{began_on_column}, #{convening_date_sql(year_column)})"
    end

    # @lat: [[retire-departed-members-safety-design#Why a stored term widens to hold a real end date, instead of narrowing#Why TermWindow.ends_on defaults to the successor's convening date]]
    def ends_on_sql(year_column = "legislator_terms.term_end_year", ended_on_column = "legislator_terms.ended_on")
      "COALESCE(#{ended_on_column}, #{convening_date_sql(year_column)})"
    end

    def current_term_condition_sql(date = Date.current)
      iso_date = (date.is_a?(String) ? Date.parse(date) : date.to_date).iso8601
      "(#{begins_on_sql} <= '#{iso_date}' AND '#{iso_date}' < #{ends_on_sql})"
    end

    private

    def cycle_anchor_and_years(sway_locale)
      rules = sway_locale.term_rules
      [rules.cycle_anchor_year, rules.cycle_years]
    end
  end
end
