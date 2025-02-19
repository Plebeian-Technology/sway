require "logger"

require "google/apis/core"

require_relative "../sway_google_cloud_storage"

namespace :sway do
  include SwayGoogleCloudStorage

  desc "Sets up a remote volume with files downloaded from a Google Cloud bucket"
  task volume_setup: :environment do
    # https://github.com/googleapis/google-cloud-ruby/tree/main/google-cloud-storage#enabling-logging
    google_logger = Logger.new($stdout)
    google_logger.level = Logger::INFO
    Google::Apis.logger = google_logger

    Rails.logger.info("sway.rake -> Download seeds file data from Google Cloud, gs://sway-assets/seeds/. Uploaded via deploy.sh script.")
    download_directory(bucket_name: "sway-assets", bucket_directory_name: "seeds", local_directory_name: "/rails/storage")

    Rails.logger.info("sway.rake -> Download geojson files from Google Cloud, gs://sway-assets/. Uploaded via deploy.sh script.")
    download_directory(bucket_name: "sway-assets", bucket_directory_name: "geojson", local_directory_name: "/rails/storage")

    backup_db
  end

  def backup_db(attempt = 0)
    Rails.logger.info("sway.rake -> backup_db attempt #{attempt}")

    if File.exist? "storage/production.sqlite3"
      Rails.logger.info("sway.rake -> Uploading production.sqlite3 to google storage as backup. Bucket - gs://sway-sqlite/production.sqlite3")
      upload_file(bucket_name: "sway-sqlite", bucket_file_path: "production_#{Time.zone.now.strftime("%Y-%m-%d_%H-%M-%S_%Z")}.sqlite3",
        local_file_path: "/rails/storage/production.sqlite3")
    elsif attempt < 5
      sleep 1
      backup_db(attempt + 1)
    end
  end
end
