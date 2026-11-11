# frozen_string_literal: true

require "sqlite3"

# @lat: [[sqlite-integrity-check-design#Why it lives in lib/]]
module SqliteIntegrityCheck
  module_function

  # @lat: [[sqlite-integrity-check-design#Why the busy-lock timeout matches database.yml]]
  BUSY_TIMEOUT_MS = 5_000

  # @lat: [[sqlite-integrity-check-design#Why production logs and never raises]]
  def run(env:, logger: Rails.logger)
    env_s = env.to_s
    return if env_s == "test"

    failures = collect_failures(env_s, logger: logger)
    return if failures.empty?

    message = "[SQLite integrity] PRAGMA quick_check failed:\n  #{failures.join("\n  ")}"
    logger.error(message)

    if env_s == "production"
      Sentry.capture_message(message, level: :error) if defined?(Sentry)
    else
      raise message
    end
  end

  def collect_failures(env_name, logger: Rails.logger)
    # @type var failures: Array[String]
    failures = []

    ActiveRecord::Base.configurations.configs_for(env_name: env_name).each do |config|
      next unless config.adapter == "sqlite3"

      db_label = "#{config.env_name}/#{config.name}"
      db_path = config.configuration_hash[:database].to_s
      next if db_path.empty?
      absolute_path = Pathname.new(db_path).absolute? ? db_path : Rails.root.join(db_path).to_s

      next unless File.exist?(absolute_path)

      result = quick_check(absolute_path)
      next if result == ["ok"]

      summary = result.first(5).inspect
      summary += " (#{result.length} total)" if result.length > 5
      failures << "#{db_label}: #{summary}"
    rescue SQLite3::BusyException => e
      # @lat: [[sqlite-integrity-check-design#Why a busy lock is skipped, not treated as a failure]]
      logger.warn(
        "[SQLite integrity] #{db_label}: skipped — database busy/locked " \
        "(#{e.message[0, 120]}); contention, not corruption"
      )
    rescue SQLite3::Exception => e
      failures << "#{db_label}: could not open (#{e.class}: #{e.message[0, 200]})"
    end

    failures
  end

  def quick_check(absolute_path)
    db = SQLite3::Database.new(absolute_path, readonly: true)
    begin
      db.busy_timeout = BUSY_TIMEOUT_MS
      db.execute("PRAGMA quick_check").flatten.compact
    ensure
      db.close
    end
  end
end
