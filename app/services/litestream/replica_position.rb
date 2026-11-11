# frozen_string_literal: true

module Litestream
  # @lat: [[replication-lag-check-internals-design#ReplicaPosition: reading the replica's position without downloading it]]
  class ReplicaPosition
    include SwayGoogleCloudStorage

    # @lat: [[replication-lag-check-internals-design#ReplicaPosition: reading the replica's position without downloading it#Why SEGMENT_NAME_PATTERN is anchored on the tail]]
    SEGMENT_NAME_PATTERN = %r{/ltx/\d+/([0-9a-fA-F]+)-([0-9a-fA-F]+)\.ltx\z}

    # @lat: [[replication-lag-check-internals-design#ReplicaPosition: reading the replica's position without downloading it#Why a bug in call's own parsing is left uncaught]]
    def call
      bucket_name = self.bucket_name
      path = self.path

      names = begin
        object_names(bucket_name: bucket_name, path: path)
      rescue => e
        return ReplicaReading.new(status: :unreadable, position: nil, bucket_name: bucket_name, path: path, error: e)
      end

      positions = names.filter_map { |name| parse_position(name) }

      if positions.empty?
        ReplicaReading.new(status: :empty, position: nil, bucket_name: bucket_name, path: path, error: nil)
      else
        ReplicaReading.new(status: :ok, position: positions.max, bucket_name: bucket_name, path: path, error: nil)
      end
    end

    private

    # @lat: [[replication-lag-check-internals-design#ReplicaPosition: reading the replica's position without downloading it#Why path and bucket_name are read per call, not class-body constants]]
    def path
      SwayDeployConfig.fetch("SWAY_LITESTREAM_PATH")
    end

    def bucket_name
      SwayDeployConfig.fetch("SWAY_GCS_BUCKET_DB")
    end

    # @lat: [[replication-lag-check-internals-design#ReplicaPosition: reading the replica's position without downloading it#Why object_names has no rescue of its own]]
    def object_names(bucket_name:, path:)
      storage
        .bucket(bucket_name, skip_lookup: true)
        .files(prefix: "#{path}/ltx/")
        .all
        .map(&:name) #: Array[untyped]
    end

    # @lat: [[replication-lag-check-internals-design#ReplicaPosition: reading the replica's position without downloading it#Why parse_position returns nil instead of raising]]
    def parse_position(name)
      match = name.match(SEGMENT_NAME_PATTERN)
      return nil unless match

      match[2].to_i(16)
    end
  end
end
