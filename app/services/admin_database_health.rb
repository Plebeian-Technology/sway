# frozen_string_literal: true

# @lat: [[admin-hub-index#Database and queue health snapshot]]
class AdminDatabaseHealth
  def self.as_props
    new.as_props
  end

  def as_props
    {
      databases: database_files,
      solid_queue_ready: safe_count { SolidQueue::ReadyExecution.count },
      solid_queue_failed: safe_count { SolidQueue::FailedExecution.count }
    }
  end

  private

  def database_files
    ActiveRecord::Base.configurations.configs_for(env_name: Rails.env).map do |db_config|
      path = db_config.database.to_s
      if path.empty? || path == ":memory:" || path.start_with?("file::memory:")
        {
          name: db_config.name.to_s,
          database_bytes: 0,
          wal_bytes: 0
        }
      else
        resolved = path.start_with?("/") ? path : Rails.root.join(path).to_s
        {
          name: db_config.name.to_s,
          database_bytes: file_size(resolved),
          wal_bytes: file_size("#{resolved}-wal")
        }
      end
    end
  end

  def file_size(path)
    return 0 if path.empty? || !File.file?(path)

    File.size(path)
  rescue SystemCallError
    0
  end

  def safe_count
    yield
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, NameError
    0
  end
end
