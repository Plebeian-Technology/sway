# frozen_string_literal: true

class PipelineLocaleLock
  class Busy < StandardError; end

  # @lat: [[bill-session-archiving#Bill session archiving#Pipeline and archive exclusion]]
  def self.with_locale(sway_locale_id, wait: true)
    locale_id = sway_locale_id.nil? ? nil : Integer(sway_locale_id)
    directory.mkpath
    gate = locale_id.nil? ? File::LOCK_EX : File::LOCK_SH
    with_file_lock("global.lock", gate, wait: wait) do
      if locale_id.nil?
        yield
      else
        with_file_lock("#{locale_id}.lock", File::LOCK_EX, wait: wait) { yield }
      end
    end
  end

  def self.directory
    database = ApplicationRecord.connection_db_config.configuration_hash.fetch(:database)
    Pathname.new("#{database}.pipeline_locks").expand_path
  end

  def self.with_file_lock(name, operation, wait:)
    File.open(directory.join(name), File::RDWR | File::CREAT, 0o600) do |lock|
      mode = wait ? operation : operation | File::LOCK_NB
      raise Busy, "Pipeline or archive operation is already running" unless lock.flock(mode)

      yield
    end
  end
  private_class_method :with_file_lock
end
