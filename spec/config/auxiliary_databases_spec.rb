# frozen_string_literal: true

require "rails_helper"
require "erb"
require "yaml"

# @lat: [[auxiliary-databases#Why cable and cache are provisioned by a migrations path]]
RSpec.describe "config/database.yml auxiliary databases" do
  let(:config) do
    YAML.safe_load(
      ERB.new(Rails.root.join("config", "database.yml").read).result,
      aliases: true
    )
  end

  let(:cache_config) do
    YAML.safe_load(
      ERB.new(Rails.root.join("config", "cache.yml").read).result,
      aliases: true
    )
  end

  # The environments that run the real adapters. Test runs the in-memory cable
  # adapter and the null cache store, so it declares neither database.
  serving_environments = %w[development production]

  describe "the cable database" do
    it "is declared with a migrations path in every serving environment" do
      serving_environments.each do |env|
        entry = config.fetch(env)["cable"]

        expect(entry).to be_a(Hash),
          "config/database.yml #{env} declares no cable database, but config/cable.yml " \
          "sends broadcasts to one. Solid Cable would fail to connect on boot."
        expect(entry["migrations_paths"]).to eq("db/cable_migrate"),
          "the cable database needs migrations_paths so the deploy's own db:migrate " \
          "creates its table. A database described only by a schema file is what cost " \
          "three failed deploys for the queue database."
      end
    end
  end

  describe "the cache database" do
    it "is declared with a migrations path in every serving environment" do
      serving_environments.each do |env|
        entry = config.fetch(env)["cache"]

        expect(entry).to be_a(Hash),
          "config/database.yml #{env} declares no cache database, but config/cache.yml " \
          "names `cache`. SolidCache::Record would fail to connect on boot."
        expect(entry["migrations_paths"]).to eq("db/cache_migrate"),
          "the cache database needs migrations_paths, for the reason on the cable " \
          "database above."
      end
    end

    it "sends Solid Cache to that database, and gives test none" do
      serving_environments.each do |env|
        expect(cache_config.fetch(env)["database"]).to eq("cache")
      end

      expect(cache_config.fetch("test")["database"]).to be_nil,
        "test runs :null_store. Naming a cache database there would build a file " \
        "nothing reads and make SolidCache::Record connect to a database that " \
        "config/database.yml does not declare for test."
    end

    # @lat: [[auxiliary-databases#What bounds the cache database's growth]]
    it "bounds how large it may grow in every serving environment" do
      serving_environments.each do |env|
        options = cache_config.fetch(env)["store_options"]

        expect(options).to be_a(Hash),
          "config/cache.yml #{env} sets no store_options. Solid Cache defaults " \
          "max_size to nil, so the cache file would grow until the disk that also " \
          "carries the primary database filled."
        expect(options["max_age"]).to be_a(Integer).and(be_positive)
        expect(options["max_size"]).to be_a(Integer).and(be_positive)
      end
    end

    # @lat: [[auxiliary-databases#What bounds the cache database's growth]]
    it "keeps the ceilings under store_options, where the gem reads them" do
      serving_environments.each do |env|
        entry = cache_config.fetch(env)

        expect(entry.keys).to include("store_options")
        expect(entry.keys & %w[max_age max_size max_entries]).to be_empty,
          "config/cache.yml #{env} names a store option beside `database`. " \
          "SolidCache::Configuration takes a fixed keyword list, so an unknown " \
          "key there raises ArgumentError before the app finishes booting."
      end
    end
  end

  # @lat: [[auxiliary-databases#Why the queue database names a migrations path]]
  it "names a migrations path for the queue database, and one that exists" do
    serving_environments.each do |env|
      entry = config.fetch(env)["queue"]

      expect(entry).to be_a(Hash)
      expect(entry["migrations_paths"]).to eq("db/queue_migrate"),
        "the queue entry in #{env} names no migrations path. Rails falls back to db/migrate " \
        "for a config that declares none, so db:migrate would run the whole application's " \
        "migrations against the background-job database."

      expect(Rails.root.glob("#{entry["migrations_paths"]}/*.rb")).not_to be_empty,
        "the queue entry in #{env} names #{entry["migrations_paths"]}, which holds no migration. " \
        "A path over an empty folder reads exactly like one that works."
    end
  end

  it "sets mmap_size to 64 MB on primary and disables mmap on auxiliary databases" do
    serving_environments.each do |env|
      primary_pragmas = config.fetch(env).dig("primary", "pragmas")
      expect(primary_pragmas["mmap_size"]).to eq(64.megabytes)

      %w[queue cable cache].each do |aux_db|
        aux_pragmas = config.fetch(env).dig(aux_db, "pragmas")
        expect(aux_pragmas["mmap_size"]).to eq(0)
        expect(aux_pragmas["journal_mode"]).to eq("WAL")
        expect(aux_pragmas["cache_size"]).to eq(2_000)
      end
    end
  end

  # @lat: [[auxiliary-databases#Why default pragmas keep temporary storage in memory]]
  it "sets temp_store to MEMORY across primary, auxiliary, and test databases" do
    serving_environments.each do |env|
      primary_pragmas = config.fetch(env).dig("primary", "pragmas")
      expect(primary_pragmas["temp_store"]).to eq("MEMORY")

      %w[queue cable cache].each do |aux_db|
        aux_pragmas = config.fetch(env).dig(aux_db, "pragmas")
        expect(aux_pragmas["temp_store"]).to eq("MEMORY")
      end
    end

    expect(config.dig("test", "pragmas", "temp_store")).to eq("MEMORY")
  end

  # Every migrations path a database entry names has to be a real folder with a
  # migration in it, or db:migrate silently does nothing and the table is
  # missing only on a machine built from an empty disk.
  it "backs each migrations path with at least one migration" do
    declared = serving_environments.flat_map { |env|
      config.fetch(env).values.filter_map { |entry|
        entry["migrations_paths"] if entry.is_a?(Hash)
      }
    }.uniq

    expect(declared).not_to be_empty, "found no migrations paths to check"

    declared.each do |path|
      migrations = Rails.root.glob("#{path}/*.rb")

      expect(migrations).not_to be_empty,
        "config/database.yml names #{path} as a migrations path, but no migration " \
        "lives there. db:migrate would report success and create no table, and the " \
        "gap would only show on a machine built from an empty disk."
    end
  end
end
