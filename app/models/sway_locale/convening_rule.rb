# frozen_string_literal: true

class SwayLocale
  # @lat: [[term-rules-design#Why Baltimore uses one convening rule for all 16 legislators]]
  class ConveningRule
    def date_in(year)
      raise NotImplementedError, "#{self.class} must say which day a term begins"
    end

    def sql_date_expr(year_column)
      raise NotImplementedError, "#{self.class} must say which day a term begins in SQL"
    end
  end
end
