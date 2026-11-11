# frozen_string_literal: true

require "fileutils"
require "securerandom"
require "google/cloud/storage"

# @lat: [[sway-google-cloud-storage#Why dependencies are required explicitly]]
require_relative "sway_logging"
require_relative "sway_deploy_config"

module SwayGoogleCloudStorage
  extend ActiveSupport::Concern

  class ListedFile < Data.define(:name, :size, :created_at, :md5)
    def initialize(name:, size:, created_at:, md5: nil)
      super
    end
  end

  # @lat: [[deploy-config-lookup-order#Why there is no fourth step]]
  GOOGLE_CLOUD_PROJECT_ID = SwayDeployConfig.fetch("SWAY_GCP_PROJECT_ID")

  BUCKETS = {
    ASSETS: SwayDeployConfig.fetch("SWAY_GCS_BUCKET_ASSETS")
  }

  # @lat: [[sway-google-cloud-storage#What the bucket says about caching audio]]
  AUDIO_CACHE_CONTROL = "public, max-age=604800"

  BUCKET_CORS_ORIGINS = [
    "https://localhost:3333",
    "https://localhost:3000",
    "http://localhost:3333",
    "http://localhost:3000",
    "https://sway.vote",
    "https://app.sway.vote",
    "https://www.sway.vote"
  ].freeze

  class << self
    def bucket_cors_origins
      extra = SwayDeployConfig["SWAY_GCS_EXTRA_CORS_ORIGINS"].to_s.split(",").map(&:strip).reject(&:empty?)
      (BUCKET_CORS_ORIGINS + extra).uniq
    end

    # @lat: [[sway-google-cloud-storage#Browser uploads depend on the live bucket policy]]
    def configure(bucket_name:)
      bucket = storage.bucket bucket_name

      bucket.cors do |c|
        c.clear
        c.add_rule bucket_cors_origins,
          %w[PUT GET],
          headers: %w[
            Content-Type
            Content-MD5
            Content-Disposition
            x-goog-content-length-range
            x-goog-resumable
          ],
          max_age: 3600
      end

      SwayLogging.info "SwayGoogleCloudStorage.configure - Set CORS policies for bucket #{bucket_name}"
    end

    def storage
      Google::Cloud.storage(
        GOOGLE_CLOUD_PROJECT_ID,
        credentials
      )
    end

    def credentials
      path = keyfile_path

      if Rails.env.production?
        SwayLogging.debug("SwayGoogleCloudStorage.credentials - google storage credentials present? #{Rails.application.credentials.dig(:google, :storage).present?}")

        payload = {
          type: Rails.application.credentials.dig(:google, :storage, :type),
          project_id: Rails.application.credentials.dig(:google, :storage, :project_id),
          private_key_id: Rails.application.credentials.dig(:google, :storage, :private_key_id),
          # @lat: [[sway-google-cloud-storage#Why credentials tolerates a nil private key at boot]]
          private_key: Rails.application.credentials.dig(:google, :storage, :private_key)&.gsub("\\n", "\n"),
          client_email: Rails.application.credentials.dig(:google, :storage, :client_email),
          client_id: Rails.application.credentials.dig(:google, :storage, :client_id),
          auth_uri: Rails.application.credentials.dig(:google, :storage, :auth_uri),
          token_uri: Rails.application.credentials.dig(:google, :storage, :token_uri),
          auth_provider_x509_cert_url: Rails.application.credentials.dig(:google, :storage, :auth_provider_x509_cert_url),
          client_x509_cert_url: Rails.application.credentials.dig(:google, :storage, :client_x509_cert_url),
          universe_domain: Rails.application.credentials.dig(:google, :storage, :universe_domain)
        }.to_json

        write_keyfile(path, payload)
      end

      path
    end

    # @lat: [[keyfile-write-directory#Why write_keyfile controls its own disk writes#The path is a method, and the client is memoized]]
    def keyfile_path
      File.absolute_path(Rails.root.join("keys", "sway-bucket-storage.json"))
    end

    # @lat: [[explanation/keyfile-write-directory#Why write_keyfile controls its own disk writes]]
    def write_keyfile(path, payload)
      FileUtils.mkdir_p(File.dirname(path))

      if File.exist?(path) && File.read(path) == payload
        File.chmod(0o600, path) if (File.stat(path).mode & 0o777) != 0o600
        return
      end

      File.open(path, "w") do |f|
        f.chmod(0o600)
        f.write(payload)
      end
    end
  end

  def generate_get_signed_url_v4(bucket_name:, file_name:)
    return unless bucket_name.present? && file_name.present?

    storage_expiry_time = 5 * 60

    storage.signed_url bucket_name, file_name, method: "GET", expires: storage_expiry_time, version: :v4
  end

  def generate_put_signed_url_v4(bucket_name:, file_name:, content_type:)
    return unless bucket_name.present? && file_name.present?

    storage_expiry_time = 5 * 60

    storage.signed_url(
      bucket_name,
      file_name,
      method: "PUT",
      expires: storage_expiry_time,
      version: :v4,
      headers: {"Content-Type" => content_type.presence || "image/png"}
    )
  end

  def upload_file(bucket_name:, bucket_file_path:, local_file_path:, cache_control: nil)
    return unless bucket_name && bucket_file_path && local_file_path

    bucket = storage.bucket bucket_name, skip_lookup: true
    bucket.create_file local_file_path, bucket_file_path, cache_control: cache_control
  end

  def download_file(bucket_name:, bucket_file_path:, local_file_path:)
    return unless bucket_name.present? && bucket_file_path.present? && local_file_path.present?

    bucket = storage.bucket bucket_name, skip_lookup: true

    file = bucket.file bucket_file_path
    abbreviated_file_path = local_file_path.split("/")[0..-2]&.join("/")
    return nil if abbreviated_file_path.blank?

    download_to_path(file, local_file_path)
  end

  def download_directory(bucket_name:, bucket_directory_name:, local_directory_name:)
    return unless bucket_name.present? && bucket_directory_name.present? && local_directory_name.present?

    bucket = storage.bucket bucket_name, skip_lookup: true

    dir = bucket.files prefix: "#{bucket_directory_name}/"

    dir.all do |f|
      download_to_path(f, "#{local_directory_name}/#{f.name}")
    end
  end

  def list_files(bucket_name:, prefix:)
    return [] unless bucket_name.present? && prefix.present?

    bucket = storage.bucket bucket_name, skip_lookup: true

    bucket.files(prefix: prefix).all.map do |file|
      ListedFile.new(name: file.name, size: file.size, created_at: file.created_at, md5: file.md5)
    end
  end

  def delete_file(bucket_name:, file_name:)
    return unless bucket_name.present? && file_name.present?
    return if file_name.starts_with? "https://"

    bucket = storage.bucket bucket_name, skip_lookup: true
    file = bucket.file file_name

    if file.present?
      file.delete
    else
      SwayLogging.warn("SwayGoogleCloudStorage.delete_file -> File #{file_name} does NOT exist. Skipping deletion.")
    end
  end

  private

  # @lat: [[sway-google-cloud-storage#Why a download lands through a temporary file]]
  def download_to_path(file, local_path)
    path = Pathname(local_path)
    FileUtils.mkdir_p(path.dirname)
    tmp_path = path.dirname.join(".#{path.basename}.download-#{Process.pid}-#{SecureRandom.hex(4)}")

    file.download(tmp_path.to_s)
    File.rename(tmp_path, path)
    path
  rescue
    tmp_path.delete if tmp_path&.exist?
    raise
  end

  def storage
    # @lat: [[keyfile-write-directory#Why write_keyfile controls its own disk writes#The path is a method, and the client is memoized]]
    @storage ||= SwayGoogleCloudStorage.storage
  end

  def credentials
    @credentials ||= SwayGoogleCloudStorage.credentials
  end
end
