# frozen_string_literal: true

require "fileutils"

# @lat: [[auxiliary-databases#How a table the schema file gains reaches a database that already exists]]
class QueueDatabaseSetupService
  QUEUE_DATABASE_NAME = "queue"

  # @lat: [[auxiliary-databases#How a table the schema file gains reaches a database that already exists]]
  JOBS_TABLE = "solid_queue_jobs"

  SCHEMA_PATH = "db/queue_schema.rb"

  SCRATCH_DATABASE = "queue_schema_scratch.sqlite3"

  def call
    config = queue_config
    return log(:not_configured, "no separate job database in #{Rails.env}") if config.nil?

    objects = schema_objects

    ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(config) do |connection|
      unless connection.table_exists?(JOBS_TABLE)
        ActiveRecord::Tasks::DatabaseTasks.load_schema(config, :ruby)
        return log(:created, "built the job tables from db/queue_schema.rb")
      end

      missing = objects.map { |_type, table, _sql| table }.uniq - connection.tables
      return log(:already_there, "job tables already present") if missing.empty?

      objects.each do |_type, table, sql|
        connection.execute(sql) if missing.include?(table)
      end

      log(:extended, "added #{missing.join(", ")} from db/queue_schema.rb")
    end
  end

  private

  # @lat: [[auxiliary-databases#How a table the schema file gains reaches a database that already exists]]
  def schema_objects
    @schema_objects ||= begin
      path = Rails.root.join("tmp", SCRATCH_DATABASE)
      FileUtils.mkdir_p(path.dirname)
      FileUtils.rm_f(path)

      scratch = ActiveRecord::DatabaseConfigurations::HashConfig.new(
        Rails.env,
        "queue_schema_scratch",
        {adapter: "sqlite3", database: path.to_s}
      )

      begin
        ActiveRecord::Tasks::DatabaseTasks.with_temporary_connection(scratch) do |connection|
          ActiveRecord::Tasks::DatabaseTasks.load_schema(scratch, :ruby, Rails.root.join(SCHEMA_PATH).to_s)

          connection.select_rows(
            "SELECT type, tbl_name, sql FROM sqlite_master " \
            "WHERE type IN ('table', 'index') AND sql IS NOT NULL " \
            "AND tbl_name NOT LIKE 'sqlite_%'"
          )
        end
      ensure
        FileUtils.rm_f([path, "#{path}-wal", "#{path}-shm"])
      end
    end
  end

  def queue_config
    ActiveRecord::Base.configurations
      .configs_for(env_name: Rails.env)
      .find { |candidate| candidate.name == QUEUE_DATABASE_NAME }
  end

  def log(outcome, message)
    SwayLogging.info("QueueDatabaseSetupService -> #{message}")
    outcome
  end
end
