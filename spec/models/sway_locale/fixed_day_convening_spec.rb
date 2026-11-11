# frozen_string_literal: true

require "rails_helper"

# The shape of rule used where a law names a calendar day outright. Congress is
# the only locale of this shape today.
RSpec.describe SwayLocale::FixedDayConvening do
  it "returns the same day every year, whatever weekday it falls on" do
    # U.S. Const. Amend. XX §1 — the 3rd day of January.
    rule = described_class.new(month: 1, day: 3)

    expect(rule.date_in(2025)).to eq(Date.new(2025, 1, 3))
    expect(rule.date_in(2023)).to eq(Date.new(2023, 1, 3))
    expect(rule.date_in(1991)).to eq(Date.new(1991, 1, 3))
  end

  it "produces identical SQL and Ruby convening dates across years" do
    rule = described_class.new(month: 1, day: 3)
    [1991, 2000, 2023, 2024, 2025, 2028].each do |year|
      sql_date = ActiveRecord::Base.connection.select_value("SELECT #{rule.sql_date_expr(year.to_s)}")
      expect(sql_date).to eq(rule.date_in(year).iso8601)
    end
  end
end
