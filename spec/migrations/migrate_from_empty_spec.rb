# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# @lat: [[migrate-from-empty-spec-design#The failure pattern]]
RSpec.describe "Building the database from nothing" do
  it "applies every migration in order, and applies all of them" do
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

    stdout, stderr, status = Dir.mktmpdir("sway-migrate-from-empty") do |dir|
      # @lat: [[migrate-from-empty-spec-design#Why the migration runs through Sway::Subprocess.capture3, not Open3]]
      Sway::Subprocess.capture3(
        "/usr/bin/env",
        "DATABASE_URL=sqlite3:#{File.join(dir, "from_empty.sqlite3")}",
        "RAILS_ENV=test",
        "SWAY_ALLOW_HOST_RAILS=1",
        Rails.root.join("bin", "rails").to_s,
        "db:migrate:with_data",
        # Measured at 4 seconds. The limit is loose because the only thing it needs
        # to catch is a migration that hangs, and a slow shared machine should not
        # be reported as one.
        timeout_seconds: 600
      )
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
  end
end
