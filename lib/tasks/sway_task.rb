require "logger"
require "open-uri"
require "google/apis/core"

require_relative "../constants"
require_relative "../sway_google_cloud_storage"

class SwayTask
  include SwayGoogleCloudStorage
  extend Rake::DSL

  def self.run
    SwayTask.new.run_task
  end

  EMAIL_BLOCKLIST_TIMEOUT_SECONDS = 5

  # @lat: [[sway-task-deploy-backup-design#Why SwayTask.backup_db retries#Why download_email_blocklist bounds its network wait and keeps the existing file]]
  def self.download_email_blocklist
    SwayLogging.info("sway.rake -> Downloading email blocklist.")
    stream = OpenURI.open_uri(
      Constants::DISPOSABLE_EMAIL_BLOCKLIST_URL,
      open_timeout: EMAIL_BLOCKLIST_TIMEOUT_SECONDS,
      read_timeout: EMAIL_BLOCKLIST_TIMEOUT_SECONDS
    )
    IO.copy_stream(stream, Constants::DISPOSABLE_EMAIL_BLOCKLIST_FILE_PATH)
  rescue OpenURI::HTTPError, SocketError, SystemCallError, Timeout::Error, IOError => e
    SwayLogging.log_exception(
      "sway.rake -> Failed to download email blocklist, keeping existing blocklist.",
      exception: e,
      level: :warn
    )
  end

  def run_task
    SwayLogging.info("sway.rake -> Run Task")
    SwayTask.download_email_blocklist

    SwayLogging.info("sway.rake -> Getting Google Logger")
    google_logger = Logger.new($stdout)
    google_logger.level = Rails.env.production? ? Logger::INFO : Logger::DEBUG
    Google::Apis.logger = google_logger

    if Rails.env.production?
      assets_bucket = SwayGoogleCloudStorage::BUCKETS[:ASSETS]

      SwayLogging.info("sway.rake -> Download seeds file data from Google Cloud, gs://#{assets_bucket}/seeds/. Uploaded via deploy.sh script.")
      download_directory(bucket_name: assets_bucket, bucket_directory_name: "seeds", local_directory_name: "#{root_path}/storage")

      SwayLogging.info("sway.rake -> Download geojson files from Google Cloud, gs://#{assets_bucket}/. Uploaded via deploy.sh script.")
      download_directory(bucket_name: assets_bucket, bucket_directory_name: "geojson", local_directory_name: "#{root_path}/storage")

      backup_db
    end
  end

  # @lat: [[sway-task-deploy-backup-design#Why BackupDatabaseJob exists]]
  # @lat: [[standby-restore#The standby copy of the production database#Why a deploy makes at most one backup copy]]
  def backup_db(attempt = 0)
    guard = BootBackupGuard.new

    if attempt.zero? && !guard.backup_needed?
      SwayLogging.info(
        "sway.rake -> backup_db skipped: this deploy already backed up, or SWAY_SKIP_DB_BACKUP is set"
      )
      return
    end

    SwayLogging.info("sway.rake -> backup_db attempt #{attempt}")

    db_name = Rails.env.production? ? "production" : "development"

    case DatabaseBackupService.new(db_name: db_name).call
    when :ok
      guard.record_backup
    when :skipped
      if attempt < 5
        sleep 1
        backup_db(attempt + 1)
      end
    end
  end

  def root_path
    Rails.env.production? ? "/rails" : "."
  end

  namespace :sway do
    desc <<-EOT
    Run the SwayTask to download the email blocklist, download seeds and geojson files
    from Google Cloud Storage, and backup the database. This task is intended to be run
    during deployment to ensure that the application has the necessary data and backups in place.
    EOT
    task deploy: :environment do
      SwayTask.run
    end
  end
end
