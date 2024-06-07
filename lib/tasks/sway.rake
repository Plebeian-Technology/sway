require_relative '../sway_google_cloud_storage'

namespace :sway do
  include SwayGoogleCloudStorage

  desc 'Sets up a remote volume with files downloaded from a Google Cloud bucket'
  task volume_setup: :environment do
    download_directory(bucket_name: 'sway-sqlite', bucket_directory_name: 'seeds', local_directory_name: 'storage')
    download_directory(bucket_name: 'sway-sqlite', bucket_directory_name: 'geojson', local_directory_name: 'storage')

    if File.exist? 'storage/production.sqlite3'
      puts 'Skip getting db from bucket.'
    else
      download_file(bucket_name: 'sway-sqlite', bucket_file_path: 'production.sqlite3',
                    local_file_path: 'storage/production.sqlite3')
    end
  end
end
