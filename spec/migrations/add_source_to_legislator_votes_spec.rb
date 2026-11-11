# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "migrate", "20260429000001_add_source_to_legislator_votes")

# Tests for a migration: the Ruby code that fills the new column with a different
# value per locale. The migration has already run against the test database, so
# these examples roll it back and run it forward again, inside an example with
# transactions turned off, to make that fill-in code actually execute.
RSpec.describe "AddSourceToLegislatorVotes migration", type: :model do
  # Do not wrap each example in a transaction. SQLite commits schema changes such
  # as add_column and change_column_null immediately, and no transaction can undo
  # them.
  self.use_transactional_tests = false

  let(:migration) { AddSourceToLegislatorVotes.new }

  # Helper: save a sway_locale, bill, legislator and legislator_vote to the database
  # steep:ignore:start
  def create_locale_with_vote(city:, state:, country: "united_states")
    sway_locale = create(:sway_locale, city: city, state: state, country: country)
    district = create(:district, sway_locale: sway_locale)
    legislator = create(:legislator, district: district)
    bill = create(:bill, sway_locale: sway_locale, legislator: legislator)
    vote = create(:legislator_vote, bill: bill, legislator: legislator, source: "manual")
    [sway_locale, vote]
  end
  # steep:ignore:end

  # steep:ignore:start
  # @lat: [[add-source-legislator-votes-migration-spec-cleanup#Why cleanup follows the schema's foreign keys]]
  def cleanup_test_locales
    locale_ids = SwayLocale.where(city: %w[congress maryland baltimore]).pluck(:id)
    return if locale_ids.empty?

    delete_rows_with_dependents("sway_locales", "id", locale_ids)
  end

  def delete_rows_with_dependents(table, column, values, depth: 0)
    return if values.empty?
    raise "foreign-key chain from #{table} is deeper than expected" if depth > 12

    conn = ActiveRecord::Base.connection
    in_list = "(#{values.map { |v| conn.quote(v) }.join(",")})"
    referencing = foreign_keys_referencing(table)
    unless referencing.empty?
      ids = conn.select_values(
        "SELECT id FROM #{conn.quote_table_name(table)} WHERE #{conn.quote_column_name(column)} IN #{in_list}"
      )
      referencing.each do |child, child_column|
        delete_rows_with_dependents(child, child_column, ids, depth: depth + 1)
      end
    end

    conn.execute("DELETE FROM #{conn.quote_table_name(table)} WHERE #{conn.quote_column_name(column)} IN #{in_list}")
  end

  # Returns [child_table, column] pairs whose foreign key restricts deleting a row of table.
  def foreign_keys_referencing(table)
    @foreign_key_index ||= begin
      conn = ActiveRecord::Base.connection
      conn.tables.each_with_object(Hash.new { |h, k| h[k] = [] }) do |child, index|
        conn.foreign_keys(child).each do |fk|
          next unless fk.primary_key.to_s == "id"
          next if fk.on_delete.in?([:cascade, :nullify])

          index[fk.to_table] << [child, fk.column.to_s]
        end
      end
    end
    @foreign_key_index[table]
  end
  # steep:ignore:end

  # @lat: [[add-source-legislator-votes-migration-spec-cleanup#The order-dependent leak this guards against]]
  after { cleanup_test_locales }

  describe "predicate sanity check" do
    it "congress locale returns congress? true" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
      expect(sway_locale.congress?).to be true
    end

    it "maryland-style locale returns regional? true" do
      sway_locale = create(:sway_locale, city: "maryland", state: "maryland", country: "united_states")
      expect(sway_locale.regional?).to be true
    end

    it "baltimore-style locale returns local? true" do
      sway_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
      expect(sway_locale.local?).to be true
    end
  end

  describe "backfill (down then up)" do
    before(:all) { cleanup_test_locales }

    after(:all) do
      cleanup_test_locales
      # Leave the migration applied, so later specs still see the source column
      unless LegislatorVote.connection.column_exists?(:legislator_votes, :source)
        ActiveRecord::Migration.suppress_messages { AddSourceToLegislatorVotes.new.up }
      end
      LegislatorVote.reset_column_information
    end

    it "backfills congress/open_states/manual per locale predicate" do
      # 1. Create the records. The source column exists at this point.
      congress_locale, congress_vote = create_locale_with_vote(
        city: "congress", state: "congress", country: "united_states"
      )
      maryland_locale, maryland_vote = create_locale_with_vote(
        city: "maryland", state: "maryland", country: "united_states"
      )
      baltimore_locale, baltimore_vote = create_locale_with_vote(
        city: "baltimore", state: "maryland", country: "united_states"
      )

      # Confirm each locale answers as expected before the migration runs
      expect(SwayLocale.find(congress_locale.id).congress?).to be true
      expect(SwayLocale.find(maryland_locale.id).regional?).to be true
      expect(SwayLocale.find(baltimore_locale.id).local?).to be true

      # 2. Roll the migration back, which drops the source column
      ActiveRecord::Migration.suppress_messages { migration.down }
      LegislatorVote.reset_column_information
      expect(LegislatorVote.column_names).not_to include("source")

      # 3. Run it forward again, which re-adds the column and fills it in
      ActiveRecord::Migration.suppress_messages { migration.up }
      LegislatorVote.reset_column_information
      expect(LegislatorVote.column_names).to include("source")

      # 4. Check what it wrote into each row
      expect(congress_vote.reload.source).to eq("congress")
      expect(maryland_vote.reload.source).to eq("open_states")
      expect(baltimore_vote.reload.source).to eq("manual")
    end
  end
end
