# frozen_string_literal: true

class SwayLocale
  # @lat: [[term-rules-design#The two convening-rule wordings#NthWeekdayConvening]]
  class NthWeekdayConvening < ConveningRule
    attr_reader :month, :weekday, :ordinal, :offset_days

    def initialize(month:, weekday:, ordinal:, offset_days: 0)
      @month = month
      @weekday = weekday
      @ordinal = ordinal
      @offset_days = offset_days
      super()
    end

    def date_in(year)
      first_of_month = Date.new(year, month, 1)
      days_to_first_match = (weekday - first_of_month.cwday) % 7
      first_match = first_of_month + days_to_first_match

      first_match + ((ordinal - 1) * 7) + offset_days
    end

    def sql_date_expr(year_column)
      m = sprintf("%02d", month)
      sqlite_weekday = weekday % 7
      offset = ((ordinal - 1) * 7) + offset_days
      offset_clause = offset.zero? ? "" : ", '+#{offset} days'"
      "date(printf('%04d-#{m}-01', #{year_column}), 'weekday #{sqlite_weekday}'#{offset_clause})"
    end
  end
end
