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

    download_directory(bucket_name: "sway-sqlite", bucket_directory_name: "seeds", local_directory_name: "/rails/storage")
    download_directory(bucket_name: "sway-sqlite", bucket_directory_name: "geojson", local_directory_name: "/rails/storage")

    backup_db
  end

  def backup_db(attempt = 0)
    puts "sway.rake -> backup_db attempt #{attempt}"

    if File.exist? "storage/production.sqlite3"
      puts "sway.rake -> Uploading production.sqlite3 to google storage as backup."
      upload_file(bucket_name: "sway-sqlite", bucket_file_path: "production.sqlite3",
        local_file_path: "/rails/storage/production.sqlite3")
    elsif attempt < 5
      sleep 1
      backup_db(attempt + 1)
      # else
      #   puts 'Getting production.sqlite3 from google storage backup.'
      #   download_file(bucket_name: 'sway-sqlite', bucket_file_path: 'production.sqlite3',
      #                 local_file_path: 'storage/production.sqlite3')
    end
  end
end
