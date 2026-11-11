# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/initializers/schema_dumper_statistics.rb" do
  it "keeps SQLite's statistics table out of db/schema.rb" do
    expect(ActiveRecord::SchemaDumper.ignore_tables).to include("sqlite_stat1")
  end

  it "leaves no dump failure for it in the checked-in schema" do
    schema = Rails.root.join("db", "schema.rb").read

    expect(schema).not_to include("sqlite_stat1")
  end
end
