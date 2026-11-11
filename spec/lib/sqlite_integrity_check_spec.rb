# frozen_string_literal: true

require "rails_helper"
require "sqlite3"
require "sqlite_integrity_check"

RSpec.describe SqliteIntegrityCheck do
  let(:tmp_dir) { Dir.mktmpdir }
  let(:good_db_path) { File.join(tmp_dir, "good.sqlite3") }
  let(:bad_db_path) { File.join(tmp_dir, "bad.sqlite3") }
  let(:logger) { instance_double(Logger, error: nil, warn: nil) }

  before do
    # A healthy database: SQLite's PRAGMA quick_check answers ["ok"].
    SQLite3::Database.new(good_db_path).tap do |db|
      db.execute("CREATE TABLE t (id INTEGER)")
      db.close
    end
    # A broken one: write nonsense bytes, and quick_check reports corruption.
    File.binwrite(bad_db_path, "not a real sqlite header\x00" * 100)
  end

  after { FileUtils.remove_entry(tmp_dir) }

  def fake_config(name:, env_name:, adapter:, database:)
    instance_double(
      ActiveRecord::DatabaseConfigurations::HashConfig,
      name: name,
      env_name: env_name,
      adapter: adapter,
      configuration_hash: {database: database}
    )
  end

  def stub_configs(configs, env:)
    fake = double("AR::Base.configurations")
    allow(fake).to receive(:configs_for).with(env_name: env).and_return(configs)
    allow(ActiveRecord::Base).to receive(:configurations).and_return(fake)
  end

  describe ".run" do
    context "in test environment" do
      it "is a no-op (skips quick_check, never raises even with a bad DB)" do
        stub_configs(
          [fake_config(name: "primary", env_name: "test", adapter: "sqlite3", database: bad_db_path)],
          env: "test"
        )
        expect { described_class.run(env: "test", logger: logger) }.not_to raise_error
        expect(logger).not_to have_received(:error)
      end
    end

    context "in development environment" do
      it "is silent + does not log when all SQLite DBs pass quick_check" do
        stub_configs(
          [fake_config(name: "primary", env_name: "development", adapter: "sqlite3", database: good_db_path)],
          env: "development"
        )
        expect { described_class.run(env: "development", logger: logger) }.not_to raise_error
        expect(logger).not_to have_received(:error)
      end

      it "raises with the corrupted DB list when quick_check fails" do
        stub_configs(
          [
            fake_config(name: "primary", env_name: "development", adapter: "sqlite3", database: good_db_path),
            fake_config(name: "queue", env_name: "development", adapter: "sqlite3", database: bad_db_path)
          ],
          env: "development"
        )
        expect { described_class.run(env: "development", logger: logger) }
          .to raise_error(RuntimeError, /PRAGMA quick_check failed/)
        expect(logger).to have_received(:error).with(/quick_check failed/)
      end

      it "skips a busy/locked DB with a warning instead of raising (contention is not corruption)" do
        # Stands in for SolidQueue holding a write lock on the queue database
        # while the web process starts. quick_check then raises BusyException,
        # and that must NOT stop the app from booting.
        stub_configs(
          [fake_config(name: "queue", env_name: "development", adapter: "sqlite3", database: good_db_path)],
          env: "development"
        )
        allow(described_class).to receive(:quick_check)
          .and_raise(SQLite3::BusyException.new("database is locked"))

        expect { described_class.run(env: "development", logger: logger) }.not_to raise_error
        expect(logger).to have_received(:warn).with(%r{busy/locked}i)
        expect(logger).not_to have_received(:error)
      end

      it "skips non-existent database files (fresh boot before db:prepare)" do
        stub_configs(
          [fake_config(name: "primary", env_name: "development", adapter: "sqlite3",
            database: File.join(tmp_dir, "missing.sqlite3"))],
          env: "development"
        )
        expect { described_class.run(env: "development", logger: logger) }.not_to raise_error
      end

      it "skips non-sqlite adapters" do
        stub_configs(
          [fake_config(name: "primary", env_name: "development", adapter: "postgresql", database: "/nope")],
          env: "development"
        )
        expect { described_class.run(env: "development", logger: logger) }.not_to raise_error
      end
    end

    context "in production environment" do
      it "does NOT raise on quick_check failure (avoids boot loops)" do
        stub_configs(
          [fake_config(name: "primary", env_name: "production", adapter: "sqlite3", database: bad_db_path)],
          env: "production"
        )
        allow(Sentry).to receive(:capture_message) if defined?(Sentry)

        expect { described_class.run(env: "production", logger: logger) }.not_to raise_error
        expect(logger).to have_received(:error).with(/quick_check failed/)
      end

      it "captures to Sentry at error level when corruption is detected" do
        # @lat: [[error-reporting-in-tests#Why Sentry's methods are watched rather than the constant replaced]]
        allow(Sentry).to receive(:capture_message)
        stub_configs(
          [fake_config(name: "primary", env_name: "production", adapter: "sqlite3", database: bad_db_path)],
          env: "production"
        )

        described_class.run(env: "production", logger: logger)

        expect(Sentry).to have_received(:capture_message)
          .with(/PRAGMA quick_check failed/, level: :error)
      end
    end
  end
end
