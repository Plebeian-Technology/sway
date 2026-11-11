# frozen_string_literal: true

require "rails_helper"

# @lat: [[admin-hub-index#Database and queue health snapshot]]
RSpec.describe AdminDatabaseHealth do
  describe ".as_props" do
    it "reports SQLite database and WAL byte sizes and returns 0 when the WAL file is absent" do
      Dir.mktmpdir do |dir|
        db_with_wal = File.join(dir, "primary.sqlite3")
        File.binwrite(db_with_wal, "x" * 4096)
        File.binwrite("#{db_with_wal}-wal", "w" * 512)

        db_without_wal = File.join(dir, "queue.sqlite3")
        File.binwrite(db_without_wal, "q" * 2048)

        configs = [
          instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, name: "primary", database: db_with_wal),
          instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, name: "queue", database: db_without_wal)
        ]
        allow(ActiveRecord::Base.configurations).to receive(:configs_for).with(env_name: Rails.env).and_return(configs)
        ready_model = Class.new
        ready_model.define_singleton_method(:count) { 3 }
        failed_model = Class.new
        failed_model.define_singleton_method(:count) { 1 }
        stub_const("SolidQueue::ReadyExecution", ready_model)
        stub_const("SolidQueue::FailedExecution", failed_model)

        result = described_class.as_props

        expect(result).to eq(
          databases: [
            {name: "primary", database_bytes: 4096, wal_bytes: 512},
            {name: "queue", database_bytes: 2048, wal_bytes: 0}
          ],
          solid_queue_ready: 3,
          solid_queue_failed: 1
        )
      end
    end

    it "returns zero byte sizes for :memory:, file::memory:, and blank database paths" do
      configs = [
        instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, name: "mem", database: ":memory:"),
        instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, name: "shared_mem", database: "file::memory:?cache=shared"),
        instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, name: "blank", database: "")
      ]
      allow(ActiveRecord::Base.configurations).to receive(:configs_for).with(env_name: Rails.env).and_return(configs)
      zero_model = Class.new
      zero_model.define_singleton_method(:count) { 0 }
      stub_const("SolidQueue::ReadyExecution", zero_model)
      stub_const("SolidQueue::FailedExecution", zero_model)

      result = described_class.as_props

      expect(result[:databases]).to eq(
        [
          {name: "mem", database_bytes: 0, wal_bytes: 0},
          {name: "shared_mem", database_bytes: 0, wal_bytes: 0},
          {name: "blank", database_bytes: 0, wal_bytes: 0}
        ]
      )
    end

    it "rescues SystemCallError from File.size and returns 0" do
      Dir.mktmpdir do |dir|
        db_path = File.join(dir, "unreadable.sqlite3")
        File.binwrite(db_path, "data")
        configs = [
          instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, name: "primary", database: db_path)
        ]
        allow(ActiveRecord::Base.configurations).to receive(:configs_for).with(env_name: Rails.env).and_return(configs)
        allow(File).to receive(:size).and_raise(Errno::EACCES)
        zero_model = Class.new
        zero_model.define_singleton_method(:count) { 0 }
        stub_const("SolidQueue::ReadyExecution", zero_model)
        stub_const("SolidQueue::FailedExecution", zero_model)

        result = described_class.as_props

        expect(result[:databases]).to eq([{name: "primary", database_bytes: 0, wal_bytes: 0}])
      end
    end

    it "rescues database errors when querying Solid Queue execution counts and returns 0" do
      allow(ActiveRecord::Base.configurations).to receive(:configs_for).with(env_name: Rails.env).and_return([])

      [
        ActiveRecord::StatementInvalid.new("no such table"),
        ActiveRecord::NoDatabaseError.new("missing db"),
        ActiveRecord::ConnectionNotEstablished.new("not connected")
      ].each do |error|
        raising_model = Class.new
        raising_model.define_singleton_method(:count) { raise error }
        stub_const("SolidQueue::ReadyExecution", raising_model)
        stub_const("SolidQueue::FailedExecution", raising_model)

        result = described_class.as_props

        expect(result[:solid_queue_ready]).to eq(0)
        expect(result[:solid_queue_failed]).to eq(0)
      end
    end
  end
end
