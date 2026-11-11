# frozen_string_literal: true

class SwayLocale
  # @lat: [[term-rules-design#The two convening-rule wordings#FixedDayConvening]]
  class FixedDayConvening < ConveningRule
    attr_reader :month, :day

    def initialize(month:, day:)
      @month = month
      @day = day
      super()
    end

    def date_in(year)
      Date.new(year, month, day)
    end

    def sql_date_expr(year_column)
      m = sprintf("%02d", month)
      d = sprintf("%02d", day)
      "printf('%04d-#{m}-#{d}', #{year_column})"
    end
  end
end
