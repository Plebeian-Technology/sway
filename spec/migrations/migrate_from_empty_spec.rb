# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# @lat: [[migrate-from-empty-spec-design#The failure pattern]]
RSpec.describe "Building the database from nothing" do
  def legislator_votes_shape(connection)
    {
      columns: connection.columns("legislator_votes").map { |c| [c.name, c.type, c.null] }.sort,
      indexes: connection.indexes("legislator_votes").map { |i| [i.name, i.columns, i.unique, i.where] }.sort,
      foreign_keys: connection.foreign_keys("legislator_votes").map { |fk| [fk.column, fk.to_table] }.sort
    }
  end

  # Returns nil when the migrations never created legislator_votes.
  def built_legislator_votes_shape(database)
    connection = ActiveRecord::ConnectionAdapters::SQLite3Adapter.new(adapter: "sqlite3", database: database)
    legislator_votes_shape(connection) if connection.table_exists?("legislator_votes")
  ensure
    connection&.disconnect!
  end

  it "applies every migration in order, applies all of them, and builds legislator_votes as db/schema.rb declares it" do
    schema_path = Rails.root.join("db", "schema.rb")
    data_schema_path = Rails.root.join("db", "data_schema.rb")
    schema_before = File.read(schema_path)
    data_schema_before = File.read(data_schema_path)
    written_before = [File.mtime(schema_path), File.mtime(data_schema_path)]

    expected_versions = (
      Dir[Rails.root.join("db", "migrate", "*.rb").to_s] +
        Dir[Rails.root.join("db", "data", "*.rb").to_s]
    ).filter_map { |path| File.basename(path)[/\A(\d{14})_/, 1] }.sort

    expect(expected_versions).not_to be_empty,
      "found no migration files at all — this spec is checking nothing"

    stdout, stderr, status, built_legislator_votes = Dir.mktmpdir("sway-migrate-from-empty") do |dir|
      database = File.join(dir, "from_empty.sqlite3")
      # @lat: [[migrate-from-empty-spec-design#Why the migration runs through Sway::Subprocess.capture3, not Open3]]
      output = Sway::Subprocess.capture3(
        "/usr/bin/env",
        "DATABASE_URL=sqlite3:#{database}",
        "RAILS_ENV=test",
        "SWAY_ALLOW_HOST_RAILS=1",
        Rails.root.join("bin", "rails").to_s,
        "db:migrate:with_data",
        # Measured at 4 seconds. The limit is loose because the only thing it needs
        # to catch is a migration that hangs, and a slow shared machine should not
        # be reported as one.
        timeout_seconds: 600
      )
      [*output, built_legislator_votes_shape(database)]
    end

    # A migration prints its number when it starts and again when it finishes, so
    # the one that appears once is the one that died. Naming it turns "the deploy
    # failed" into "this file is the problem", which is the whole point of the spec.
    started = stdout.scan(/^== (\d{14}) \S+: migrating/).flatten
    finished = stdout.scan(/^== (\d{14}) \S+: migrated/).flatten
    died_on = (started - finished).first

    expect(status.success?).to be(true), <<~MESSAGE
      Sway cannot build its database from nothing.

      #{died_on ? "It stopped on migration #{died_on}." : "It failed before running any migration."}
      #{finished.length} of #{expected_versions.length} migrations were applied.

      The usual cause is a migration that names one of the app's model classes. That
      class keeps changing; the migration cannot. Give the migration its own bare
      stand-in class that knows nothing but the table name, the way
      db/migrate/20260420000001_normalize_user_phones.rb does.

      Last of what it printed:
      #{stdout.split("\n").last(25).join("\n")}
      #{stderr.split("\n").last(25).join("\n")}
    MESSAGE

    # Finishing without an error is not the same as having done the work: a chain
    # that quietly skipped a migration also exits 0.
    expect(finished.sort).to eq(expected_versions),
      "these migrations never ran: #{(expected_versions - finished).inspect}"

    # @lat: [[migrate-from-empty-spec-design#Why the schema-file check compares mtimes, not contents]]
    written_after = [File.mtime(schema_path), File.mtime(data_schema_path)]
    File.write(schema_path, schema_before) if File.read(schema_path) != schema_before
    File.write(data_schema_path, data_schema_before) if File.read(data_schema_path) != data_schema_before

    expect(written_after).to eq(written_before),
      "This run rewrote db/schema.rb or db/data_schema.rb from the throwaway database " \
      "(their contents have been put back). config/environments/test.rb must keep " \
      "dump_schema_after_migration off."

    # @lat: [[migrate-from-empty-spec-design#Comparing a migrated table with db/schema.rb]]
    declared = legislator_votes_shape(ActiveRecord::Base.connection)
    built = built_legislator_votes || {}
    expect(built).to eq(declared), <<~MESSAGE
      The migrations build a legislator_votes table that differs from the one db/schema.rb
      declares. Specs load db/schema.rb, so they run against a table a migrated database does not have.

      Only in db/schema.rb: #{declared.to_h { |key, rows| [key, rows - built.fetch(key, [])] }.inspect}
      Only from the migrations: #{built.to_h { |key, rows| [key, rows - declared.fetch(key, [])] }.inspect}
    MESSAGE
  end
end
