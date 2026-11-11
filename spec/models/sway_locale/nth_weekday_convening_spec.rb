# frozen_string_literal: true

require "rails_helper"

# The shape of rule used where a law names a weekday rather than a date. The
# day therefore moves from year to year, which is the whole reason it cannot be
# stored as a constant.
RSpec.describe SwayLocale::NthWeekdayConvening do
  it "finds the nth weekday of a month" do
    # Md. Const. Art. III §14 — the second Wednesday of January.
    rule = described_class.new(month: 1, weekday: 3, ordinal: 2)

    expect(rule.date_in(2023)).to eq(Date.new(2023, 1, 11))
    expect(rule.date_in(2025)).to eq(Date.new(2025, 1, 8))
  end

  it "counts to an anchor day and then moves on, when the law names a later day of that week" do
    # Baltimore City Charter Art. III § 2(a)(2) — the Thursday next after the
    # first Monday in December. The first Monday of December 2024 was the 2nd.
    rule = described_class.new(month: 12, weekday: 1, ordinal: 1, offset_days: 3)

    expect(rule.date_in(2024)).to eq(Date.new(2024, 12, 5))
    expect(rule.date_in(2028)).to eq(Date.new(2028, 12, 7))
  end

  it "works when the month begins on the weekday it is counting" do
    # December 2025 begins on a Monday, so the first Monday is the 1st and
    # nothing should be carried into the following week.
    rule = described_class.new(month: 12, weekday: 1, ordinal: 1)

    expect(rule.date_in(2025)).to eq(Date.new(2025, 12, 1))
  end

  it "produces identical SQL and Ruby convening dates across years and offsets" do
    md_rule = described_class.new(month: 1, weekday: 3, ordinal: 2)
    balt_rule = described_class.new(month: 12, weekday: 1, ordinal: 1, offset_days: 3)

    (2015..2032).each do |year|
      md_sql = ActiveRecord::Base.connection.select_value("SELECT #{md_rule.sql_date_expr(year.to_s)}")
      balt_sql = ActiveRecord::Base.connection.select_value("SELECT #{balt_rule.sql_date_expr(year.to_s)}")

      expect(md_sql).to eq(md_rule.date_in(year).iso8601)
      expect(balt_sql).to eq(balt_rule.date_in(year).iso8601)
    end
  end
end
