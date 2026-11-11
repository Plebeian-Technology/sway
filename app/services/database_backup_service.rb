# frozen_string_literal: true

# @lat: [[database-backup-service-design#Why backups_for_this_db anchors its regex on the timestamp]]
class DatabaseBackupService
  include SwayGoogleCloudStorage

  # @lat: [[database-backup-service-design#Why BUCKET_NAME is not written down here]]
  BUCKET_NAME = SwayDeployConfig.fetch("SWAY_GCS_BUCKET_DB")
  RETENTION_DAYS = 14

  # @lat: [[database-backup-service-design#The size-regression refusal guard]]
  MINIMUM_SIZE_RATIO = 0.5

  def initialize(db_name:, retention_days: RETENTION_DAYS)
    @db_name = db_name
    @retention_days = retention_days
  end

  def call
    return :skipped unless File.exist?(local_db_path)

    # @lat: [[database-backup-service-design#Why pruning only happens after a successful upload]]
    return :refused unless backup_and_upload

    prune_old_backups
    :ok
  end

  private

  attr_reader :db_name, :retention_days

  def local_db_path
    Rails.root.join("storage", "#{db_name}.sqlite3").to_s
  end

  # @lat: [[database-backup-service-design#Why pruning only happens after a successful upload]]
  def backup_and_upload
    backup_file_name = "#{db_name}_#{Time.current.strftime("%Y-%m-%d_%H-%M-%S_%Z")}.sqlite3"
    local_backup_path = Rails.root.join("tmp", backup_file_name).to_s

    begin
      online_backup(local_db_path, local_backup_path)

      unless File.exist?(local_backup_path) && !File.zero?(local_backup_path)
        SwayLogging.error("database_backup.empty_or_missing", db_name: db_name)
        return false
      end

      new_size = File.size(local_backup_path)
      previous_size = most_recent_backup_size

      if size_regression?(new_size, previous_size)
        report_refusal(new_size: new_size, previous_size: previous_size)
        return false
      end

      upload_file(
        bucket_name: BUCKET_NAME,
        bucket_file_path: "db/#{Rails.env}/#{backup_file_name}",
        local_file_path: local_backup_path
      )
      true
    ensure
      File.delete(local_backup_path) if File.exist?(local_backup_path)
    end
  end

  # @lat: [[database-backup-service-design#The size-regression refusal guard]]
  def size_regression?(new_size, previous_size)
    return false if previous_size.nil? || previous_size.zero?

    new_size < previous_size * MINIMUM_SIZE_RATIO
  end

  def most_recent_backup_size
    backups_for_this_db.max_by { |file| file.created_at || Time.zone.at(0) }&.size
  end

  def report_refusal(new_size:, previous_size:)
    SwayLogging.error(
      "database_backup.refused_size_regression",
      db_name: db_name,
      new_size: new_size,
      previous_size: previous_size,
      minimum_ratio: MINIMUM_SIZE_RATIO
    )

    # @lat: [[database-backup-service-design#Why a refusal reports to Sentry directly]]
    return unless Rails.env.production?

    Sentry.capture_message(
      "Database backup refused for #{db_name}: #{new_size} bytes vs #{previous_size} previously",
      level: :error
    )
  end

  def online_backup(source_path, dest_path)
    SQLite3::Database.new(source_path, readonly: true) do |source_db|
      SQLite3::Database.new(dest_path) do |backup_db|
        backup = SQLite3::Backup.new(backup_db, "main", source_db, "main")
        begin
          backup.step(5)
        end while backup.remaining > 0 # rubocop:disable Lint/Loop
        backup.finish
      end
    end
  end

  def prune_old_backups
    cutoff = retention_days.days.ago.to_time

    backups_for_this_db.each do |file|
      created = file.created_at
      next unless created && created < cutoff

      delete_file(bucket_name: BUCKET_NAME, file_name: file.name)
    end
  end

  # @lat: [[database-backup-service-design#Why backups_for_this_db anchors its regex on the timestamp]]
  def backups_for_this_db
    name_re = /\A#{Regexp.escape(db_name)}_\d{4}-\d{2}-\d{2}_/

    backups.select { |file| File.basename(file.name.to_s).match?(name_re) }
  end

  # @lat: [[database-backup-service-design#Why backups_for_this_db anchors its regex on the timestamp]]
  def backups
    @backups ||= existing_backups
  end

  def existing_backups
    list_files(bucket_name: BUCKET_NAME, prefix: "db/#{Rails.env}/")
  rescue => e
    SwayLogging.log_exception("database_backup.prune_list_failed", exception: e, level: :warn)
    [] #: Array[untyped]
  end
end
