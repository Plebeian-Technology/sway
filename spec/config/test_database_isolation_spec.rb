# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"

# @lat: [[test-database-isolation#What sharing one database file costs]]
RSpec.describe "test database isolation (config/database.yml, .dockerdev/compose.yml)" do
  let(:test_config) do
    raw = Rails.root.join("config", "database.yml").read
    YAML.safe_load(ERB.new(raw).result, aliases: true).fetch("test")
  end

  let(:rspec_service_tmpfs) do
    raw = Rails.root.join(".dockerdev", "compose.yml").read
    YAML.safe_load(raw, aliases: true).dig("services", "rspec", "tmpfs")
  end

  # ERB is re-evaluated on every read, so setting an ENV var and re-reading
  # proves the interpolation moved the path — the mutation V-3 requires, run
  # inside the spec rather than by hand. Restored in an ensure: the rest of the
  # suite runs in this same process and must not inherit a changed variable.
  def database_config_for(overrides)
    original = {} #: Hash[String, String?]
    overrides.each_key { |key| original[key] = ENV[key] }

    begin
      overrides.each do |key, value|
        value.nil? ? ENV.delete(key) : (ENV[key] = value)
      end

      raw = Rails.root.join("config", "database.yml").read
      YAML.safe_load(ERB.new(raw).result, aliases: true).fetch("test").fetch("database")
    ensure
      original.each { |key, value| value.nil? ? ENV.delete(key) : (ENV[key] = value) }
    end
  end

  it "finds the test block and a non-empty database path, so a bad path or a parse failure is a red gate" do
    database = test_config.fetch("database")

    expect(database).to be_a(String),
      "config/database.yml's test.database did not parse as a string — this whole spec would be checking nothing"
    expect(database).not_to be_empty,
      "config/database.yml's test.database parsed as an empty string — every rspec run would open no file at all"
  end

  it "falls back to storage/test.sqlite3 when neither variable is set (reversibility)" do
    path = database_config_for("SWAY_TEST_DATABASE_DIR" => nil, "TEST_ENV_NUMBER" => nil)

    expect(path).to eq("storage/test.sqlite3"),
      "the fallback moved, so every existing dip run rspec and every focused run now writes somewhere else"
  end

  # @lat: [[test-database-isolation-design#Why an empty SWAY_TEST_DATABASE_DIR is treated as unset, not as the filesystem root]]
  it "treats an empty SWAY_TEST_DATABASE_DIR as unset, not as the filesystem root" do
    path = database_config_for("SWAY_TEST_DATABASE_DIR" => "", "TEST_ENV_NUMBER" => nil)

    expect(path).to eq("storage/test.sqlite3"),
      "an empty value resolved to #{path.inspect} — off the storage volume, and discarded when the container exits"
  end

  # @lat: [[test-database-isolation-design#How the interpolation-dependent examples were verified]]
  it "resolves under SWAY_TEST_DATABASE_DIR when only the run directory is set" do
    path = database_config_for("SWAY_TEST_DATABASE_DIR" => "/testdb", "TEST_ENV_NUMBER" => nil)

    expect(path).to eq("/testdb/test.sqlite3"),
      "the run directory did not reach the path, so the per-run tmpfs mount would never be used"
  end

  # @lat: [[test-database-isolation-design#How the interpolation-dependent examples were verified]]
  it "resolves per worker when TEST_ENV_NUMBER is also set (parallel_tests convention)" do
    path = database_config_for("SWAY_TEST_DATABASE_DIR" => "/testdb", "TEST_ENV_NUMBER" => "2")

    expect(path).to eq("/testdb/test2.sqlite3"),
      "the worker number did not reach the path, so two workers in one run would share a single database file"
  end

  # @lat: [[test-database-isolation-design#How the interpolation-dependent examples were verified]]
  it "gives two different TEST_ENV_NUMBER values two different files, so each worker owns one writer" do
    first = database_config_for("SWAY_TEST_DATABASE_DIR" => "/testdb", "TEST_ENV_NUMBER" => "2")
    second = database_config_for("SWAY_TEST_DATABASE_DIR" => "/testdb", "TEST_ENV_NUMBER" => "3")

    expect(first).not_to eq(second),
      "two workers resolve to the same file, so they are two writers on one SQLite database and the run " \
      "will report failures that are really lock contention"
  end

  it "still inherits the default anchor's busy timeout, WAL mode and journal_size_limit" do
    expect(test_config["timeout"]).to eq(10_000),
      "the test: block lost the default anchor's busy timeout, so a collision would raise instead of waiting"
    expect(test_config.dig("pragmas", "journal_mode")).to eq("WAL"),
      "the test: block lost WAL mode, so a worker could no longer read while another writes"
    expect(test_config.dig("pragmas", "journal_size_limit")).to eq(64 * 1024 * 1024),
      "the test: block lost its journal_size_limit cap, so a worker's WAL file could grow unbounded"
  end

  # @lat: [[test-database-isolation-design#How the interpolation-dependent examples were verified]]
  it "declares a tmpfs list on the rspec service that keeps the inherited mounts and adds /testdb (L-03, L-04)" do
    tmpfs = rspec_service_tmpfs

    expect(tmpfs).to be_an(Array),
      "the rspec service has no tmpfs list at all — /testdb has no mount, so SWAY_TEST_DATABASE_DIR=/testdb " \
      "points at a path docker compose run has no --tmpfs flag to create"
    expect(tmpfs).not_to be_empty,
      "the rspec service's tmpfs list is empty — a YAML merge key replaces the inherited list rather than " \
      "merging it, so the rspec service loses /tmp and /app/tmp/pids the moment /testdb is declared this way"
    mount_points = tmpfs.to_a.map { |entry| entry.split(":").first }
    expect(mount_points).to contain_exactly("/tmp", "/app/tmp/pids", "/testdb"),
      "the rspec service must re-list /tmp and /app/tmp/pids alongside /testdb, or it loses its inherited " \
      "mounts when the merge key replaces rather than merges (the same hazard already documented above " \
      "the service's own volumes: list)"
  end

  # @lat: [[test-database-isolation-design#Why /testdb's tmpfs entry carries an explicit size=]]
  it "bounds the size of /testdb, so the specs writing there cannot eat the container's memory" do
    testdb = rspec_service_tmpfs.to_a.find { |entry| entry.split(":").first == "/testdb" }

    expect(testdb).not_to be_nil, "the rspec service declares no /testdb tmpfs at all"
    expect(testdb).to match(/\bsize=\d+[kmg]?\b/i),
      "the /testdb tmpfs carries no size option (#{testdb.inspect}), so it takes the kernel default of half " \
      "the VM's RAM and competes with the run's own peak"
  end
end
