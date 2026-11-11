# frozen_string_literal: true

# @lat: [[sway-task-deploy-backup-design#Why BackupDatabaseJob exists]]
class BackupDatabaseJob < ApplicationJob
  queue_as :background

  def perform
    database_names.each do |db_name|
      DatabaseBackupService.new(db_name: db_name).call
    rescue => e
      SwayLogging.log_exception(
        "backup_database_job.failed",
        exception: e,
        db_name: db_name
      )
    end
  end

  private

  # @lat: [[sway-task-deploy-backup-design#Why BackupDatabaseJob only backs up the main database]]
  def database_names
    main = Rails.env.production? ? "production" : Rails.env.to_s

    [main]
  end
end
