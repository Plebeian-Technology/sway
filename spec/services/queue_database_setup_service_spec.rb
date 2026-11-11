# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

# The one property that matters: it WRITES ONLY WHEN THERE IS NOTHING THERE.
# This runs on every boot of the public-facing machine, and loading a schema
# over existing tables destroys them.
RSpec.describe QueueDatabaseSetupService do
  self.use_transactional_tests = false

  def queue_config(path)
    ActiveRecord::DatabaseConfigurations::HashConfig.new(
      Rails.env,
      described_class::QUEUE_DATABASE_NAME,
      {adapter: "sqlite3", database: path}
    )
  end

  def only_configured(config)
    allow(ActiveRecord::Base.configurations).to receive(:configs_for).and_call_original
    allow(ActiveRecord::Base.configurations).to receive(:configs_for)
      .with(env_name: Rails.env).and_return([config])
  end

  def tables_in(config)
    ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config, &:tables)
  end

  def build_queue_database(config)
    ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do
      ActiveRecord::Tasks::DatabaseTasks.load_schema(
        config, :ruby, Rails.root.join("db", "queue_schema.rb").to_s
      )
    end
  end

  it "does nothing in an environment with no separate job database" do
    # True of the test environment, and worth pinning: it means running the whole
    # suite never reaches the database-writing path at all.
    expect(described_class.new.call).to eq(:not_configured)
  end

  it "builds the tables when the jobs table is missing" do
    config = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, name: "queue")
    connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
    allow(connection).to receive(:table_exists?).with("solid_queue_jobs").and_return(false)
    only_configured(config)
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:with_temporary_connection).and_call_original
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:with_temporary_connection)
      .with(config).and_yield(connection)
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:load_schema)

    expect(described_class.new.call).to eq(:created)
    expect(ActiveRecord::Tasks::DatabaseTasks).to have_received(:load_schema).with(config, :ruby)
  end

  # The safety example. A machine that has been serving the public for months has
  # these tables, with jobs waiting in them.
  it "writes nothing when every table the schema file names is already there" do
    Dir.mktmpdir do |dir|
      config = queue_config(File.join(dir, "queue.sqlite3"))
      build_queue_database(config)
      only_configured(config)
      allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:load_schema).and_call_original

      expect(described_class.new.call).to eq(:already_there)
      expect(ActiveRecord::Tasks::DatabaseTasks).not_to have_received(:load_schema).with(config, :ruby)
    end
  end

  it "adds a table the schema file names to a database that already holds jobs" do
    Dir.mktmpdir do |dir|
      config = queue_config(File.join(dir, "queue.sqlite3"))
      build_queue_database(config)
      ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |connection|
        connection.drop_table("solid_queue_batch_executions")
        connection.drop_table("solid_queue_batches")
      end
      only_configured(config)

      expect(described_class.new.call).to eq(:extended)
      expect(tables_in(config)).to include("solid_queue_batches", "solid_queue_batch_executions")
    end
  end

  it "leaves no throwaway database behind" do
    Dir.mktmpdir do |dir|
      config = queue_config(File.join(dir, "queue.sqlite3"))
      build_queue_database(config)
      only_configured(config)

      described_class.new.call

      scratch = Rails.root.join("tmp", described_class::SCRATCH_DATABASE)
      expect(File.exist?(scratch)).to be(false)
      expect(File.exist?("#{scratch}-wal")).to be(false)
      expect(File.exist?("#{scratch}-shm")).to be(false)
    end
  end

  it "leaves the rows in the tables it did not add" do
    Dir.mktmpdir do |dir|
      config = queue_config(File.join(dir, "queue.sqlite3"))
      build_queue_database(config)
      ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |connection|
        connection.drop_table("solid_queue_batches")
        connection.execute(
          "INSERT INTO solid_queue_jobs (queue_name, class_name, arguments, priority, created_at, updated_at) " \
          "VALUES ('background', 'AJob', '{}', 0, datetime('now'), datetime('now'))"
        )
      end
      only_configured(config)

      expect(described_class.new.call).to eq(:extended)

      jobs = ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) { |connection|
        connection.select_value("SELECT COUNT(*) FROM solid_queue_jobs")
      }
      expect(jobs).to eq(1)
    end
  end

  # It has to look past the main database to find the job one. Getting this wrong
  # would point the schema load at the wrong database entirely.
  it "picks the job database out of the list, not the first one it sees" do
    primary = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, name: "primary")
    queue = instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, name: "queue")
    connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
    allow(connection).to receive(:table_exists?).with("solid_queue_jobs").and_return(false)
    allow(ActiveRecord::Base.configurations).to receive(:configs_for).and_call_original
    allow(ActiveRecord::Base.configurations).to receive(:configs_for)
      .with(env_name: Rails.env).and_return([primary, queue])
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:with_temporary_connection).and_call_original
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:with_temporary_connection)
      .with(queue).and_yield(connection)
    allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:load_schema)

    expect(described_class.new.call).to eq(:created)
    expect(ActiveRecord::Tasks::DatabaseTasks).to have_received(:load_schema).with(queue, :ruby)
  end
end
