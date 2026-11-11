# frozen_string_literal: true

require "rails_helper"

RSpec.describe AnalyzeDatabaseJob do
  describe "#perform" do
    it "leaves statistics the query planner can read" do
      create(:sway_locale)
      ActiveRecord::Base.connection.execute("DELETE FROM sqlite_stat1") if statistics_table_exists?

      rows = described_class.new.perform

      expect(rows).to be_positive
      expect(analyzed_tables).to include("sway_locales")
    end

    it "caps how many rows each index is sampled over" do
      described_class.new.perform

      limit = ActiveRecord::Base.connection.select_value("PRAGMA analysis_limit").to_i
      expect(limit).to eq(described_class::ANALYSIS_LIMIT)
    end
  end

  def statistics_table_exists?
    ActiveRecord::Base.connection.select_value(
      "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'sqlite_stat1'"
    ).to_i.positive?
  end

  def analyzed_tables
    ActiveRecord::Base.connection.select_values("SELECT tbl FROM sqlite_stat1")
  end
end
