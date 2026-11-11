# frozen_string_literal: true

module Legislation
  # @lat: [[legislation-artifact-backup#Why the application's credentials cannot delete]]
  class ArtifactBucket
    include SwayGoogleCloudStorage

    def initialize(bucket_name: nil)
      @bucket_name = bucket_name
    end

    # @lat: [[legislation-artifact-backup#Why the bucket name is resolved on use rather than on load]]
    def bucket_name
      @bucket_name ||= SwayDeployConfig.fetch("SWAY_GCS_BUCKET_LEGISLATION")
    end

    def upload(object_name:, local_path:)
      upload_file(bucket_name: bucket_name, bucket_file_path: object_name, local_file_path: local_path.to_s)
      nil
    end

    # @lat: [[legislation-artifact-backup#Why a restore fetches one object at a time]]
    def download(object_name:, local_path:)
      download_file(bucket_name: bucket_name, bucket_file_path: object_name, local_file_path: local_path.to_s)
      nil
    end

    def list(prefix:)
      list_files(bucket_name: bucket_name, prefix: prefix)
    end
  end
end
