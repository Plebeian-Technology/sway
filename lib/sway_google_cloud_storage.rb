# typed: true

require "google/cloud/storage"

# pre-signed urls
# https://cloud.google.com/storage/docs/access-control/signing-urls-with-helpers#client-libraries
# private writes, public reads
# https://cloud.google.com/storage/docs/access-control/making-data-public

module SwayGoogleCloudStorage
  extend ActiveSupport::Concern
  extend T::Sig

  GOOGLE_CLOUD_PROJECT_ID = "sway-421916"

  BUCKETS = {
    ASSETS: "sway-assets"
  }

  class << self
    extend T::Sig
    # Expose the bucket to cors requests from the frontend
    # https://cloud.google.com/storage/docs/using-cors#client-libraries

    sig { params(bucket_name: String).void }
    def configure(bucket_name:)
      # The ID of your GCS bucket
      # bucket_name = "your-unique-bucket-name"

      storage = Google::Cloud.storage(
        GOOGLE_CLOUD_PROJECT_ID,
        File.absolute_path("config/keys/sway-bucket-storage.json")
      )
      bucket = storage.bucket bucket_name

      bucket.cors do |c|
        c.add_rule ["https://localhost:3000", "https://sway.vote", "https://app.sway.vote"],
          %w[PUT GET],
          headers: %w[
            Content-Type
            x-goog-resumable
          ],
          max_age: 3600
      end

      Rails.logger.info "SwayGoogleCloudStorage.configure - Set CORS policies for bucket #{bucket_name}"
    end
  end

  sig { params(bucket_name: String, file_name: String).void }
  def generate_get_signed_url_v4(bucket_name:, file_name:)
    return unless bucket_name.present? && file_name.present?

    storage_expiry_time = 5 * 60 # 5 minutes

    storage.signed_url bucket_name, file_name, method: "GET", expires: storage_expiry_time, version: :v4
  end

  sig { params(bucket_name: String, file_name: String, content_type: String).void }
  def generate_put_signed_url_v4(bucket_name:, file_name:, content_type:)
    return unless bucket_name.present? && file_name.present?

    storage_expiry_time = 5 * 60 # 5 minutes

    storage.signed_url(
      bucket_name,
      file_name,
      method: "PUT",
      expires: storage_expiry_time,
      version: :v4,
      headers: {"Content-Type" => content_type.presence || "image/png"}
    )
  end

  def upload_file(bucket_name:, bucket_file_path:, local_file_path:)
    return unless bucket_name && bucket_file_path && local_file_path

    bucket = storage.bucket bucket_name, skip_lookup: true
    bucket.create_file local_file_path, bucket_file_path
  end

  sig { params(bucket_name: String, bucket_file_path: String, local_file_path: String).void }
  def download_file(bucket_name:, bucket_file_path:, local_file_path:)
    return unless bucket_name.present? && bucket_file_path.present? && local_file_path.present?

    bucket = storage.bucket bucket_name, skip_lookup: true

    file = bucket.file bucket_file_path
    abbreviated_file_path = local_file_path.split("/")[0..-2]&.join("/")
    return nil if abbreviated_file_path.blank?

    FileUtils.mkdir_p(abbreviated_file_path)
    file.download local_file_path
  end

  sig { params(bucket_name: String, bucket_directory_name: String, local_directory_name: String).void }
  def download_directory(bucket_name:, bucket_directory_name:, local_directory_name:)
    return unless bucket_name.present? && bucket_directory_name.present? && local_directory_name.present?

    bucket = storage.bucket bucket_name, skip_lookup: true

    dir = bucket.files prefix: "#{bucket_directory_name}/"

    dir.all do |f|
      FileUtils.mkdir_p("#{local_directory_name}/#{f.name.split("/")[0..-2].join("/")}")
      f.download "#{local_directory_name}/#{f.name}"
    end
  end

  sig { params(bucket_name: String, file_name: T.nilable(String)).void }
  def delete_file(bucket_name:, file_name:)
    return unless bucket_name.present? && file_name.present?
    return if file_name.starts_with? "https://"

    bucket = storage.bucket bucket_name, skip_lookup: true
    file = bucket.file file_name

    file.delete
  end

  private

  def storage
    @_storage = if Rails.env.production?
      Google::Cloud.storage
    else
      Google::Cloud.storage(
        GOOGLE_CLOUD_PROJECT_ID,
        File.absolute_path("config/keys/sway-bucket-storage.json")
      )
    end
    @_storage
  end
end
