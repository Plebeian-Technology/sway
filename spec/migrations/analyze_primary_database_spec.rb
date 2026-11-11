# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "migrate", "20260905100004_analyze_primary_database.rb").to_s

RSpec.describe AnalyzePrimaryDatabase do
  it "writes statistics into a database that has never been analyzed" do
    create(:sway_locale)
    ActiveRecord::Base.connection.execute("DROP TABLE IF EXISTS sqlite_stat1")

    described_class.new.up

    rows = ActiveRecord::Base.connection.select_all("SELECT tbl, stat FROM sqlite_stat1").to_a
    expect(rows).not_to be_empty
  end
end
