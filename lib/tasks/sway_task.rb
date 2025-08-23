# typed: true

require "logger"
require "open-uri"
require "google/apis/core"

require_relative "../constants"
require_relative "../sway_google_cloud_storage"

class SwayTask
  include SwayGoogleCloudStorage
  extend Rake::DSL
  extend T::Sig

  def self.run
    SwayTask.new.run_task
  end

  def self.download_email_blocklist
    Rails.logger.info("sway.rake -> Downloading email blocklist.")
    # IO.copy_stream(OpenURI.open(Constants::DISPOSABLE_EMAIL_BLOCKLIST_URL), Constants::DISPOSABLE_EMAIL_BLOCKLIST_FILE_PATH)
    IO.copy_stream(T.cast(T.unsafe(OpenURI).open_uri(Constants::DISPOSABLE_EMAIL_BLOCKLIST_URL), IO), Constants::DISPOSABLE_EMAIL_BLOCKLIST_FILE_PATH)
  rescue
  end

  def run_task
    SwayTask.download_email_blocklist

    # https://github.com/googleapis/google-cloud-ruby/tree/main/google-cloud-storage#enabling-logging
    google_logger = Logger.new($stdout)
    google_logger.level = Rails.env.production? ? Logger::INFO : Logger::DEBUG
    Google::Apis.logger = google_logger

    if Rails.env.production?
      Rails.logger.info("sway.rake -> Download seeds file data from Google Cloud, gs://sway-assets/seeds/. Uploaded via deploy.sh script.")
      download_directory(bucket_name: "sway-assets", bucket_directory_name: "seeds", local_directory_name: "#{root_path}/storage")

      Rails.logger.info("sway.rake -> Download geojson files from Google Cloud, gs://sway-assets/. Uploaded via deploy.sh script.")
      download_directory(bucket_name: "sway-assets", bucket_directory_name: "geojson", local_directory_name: "#{root_path}/storage")
    end

    backup_db
  end

  def backup_db(attempt = 0)
    Rails.logger.info("sway.rake -> backup_db attempt #{attempt}")

    db_name = Rails.env.production? ? "production" : "development"

    if File.exist? "storage/#{db_name}.sqlite3"
      Rails.logger.info("sway.rake -> Uploading #{db_name}.sqlite3 to google storage as backup. Bucket - gs://sway-sqlite/#{db_name}.sqlite3")

      backup_file_name = "#{db_name}_#{Time.zone.now.strftime("%Y-%m-%d_%H-%M-%S_%Z")}.sqlite3"
      local_backup_path = "#{root_path}/tmp/#{backup_file_name}"
      local_db_path = "#{root_path}/storage/#{db_name}.sqlite3"

      backup_sqlite_database_online(local_db_path, local_backup_path) do
        if File.zero?(local_backup_path)
          Rails.logger.error("sway.rake.backup_db -> Cannot back up database. File #{local_backup_path} is empty!")
        else
          upload_file(
            bucket_name: "sway-sqlite",
            bucket_file_path: "db/#{Rails.env}/#{backup_file_name}",
            local_file_path: local_backup_path
          )
        end
      end
    elsif attempt < 5
      sleep 1
      backup_db(attempt + 1)
    end
  end

  def backup_sqlite_database_online(local_db_path, local_backup_path, &block)
    # Use a separate connection for the backup to avoid interfering with the main database operations.
    source_db = SQLite3::Database.new(local_db_path, readonly: true) # Open the main database in read-only mode
    backup_db = SQLite3::Database.new(local_backup_path)  # Create the backup database *first*

    # Perform the backup (copy from the live database to the backup database)
    backup = SQLite3::Backup.new(backup_db, "main", source_db, "main")

    # https://sparklemotion.github.io/sqlite3-ruby/SQLite3/Backup.html
    begin
      backup.step(5) #=> OK or DONE
      Rails.logger.debug("sway.rake.backup -> #{backup.remaining} / #{backup.pagecount} database pages remaining to backup.")
    end while backup.remaining > 0 # rubocop:disable Lint/Loop

    # Rails.logger.info("sway.rake.backup -> Close backup_db")
    # backup_db.close

    Rails.logger.info("sway.rake.backup -> Close source_db")
    # source_db.close

    Rails.logger.info("sway.rake.backup -> yield")
    yield

    Rails.logger.info("sway.rake.backup -> Finish backup")
    backup.finish # Destroy backup object
    File.delete(local_backup_path)
  rescue => e
    Rails.logger.info("Error backing up database: #{e.message}")
    nil
  end

  def root_path
    Rails.env.production? ? "/rails" : "."
  end

  namespace :sway do
    desc "Sets up a remote volume with files downloaded from a Google Cloud bucket"
    task volume_setup: :environment do
      SwayTask.run
    end
  end
end
