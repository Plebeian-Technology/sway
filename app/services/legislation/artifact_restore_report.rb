# frozen_string_literal: true

module Legislation
  class ArtifactRestoreReport
    FAILURE_SAMPLE_LIMIT = 50

    attr_accessor :status
    attr_accessor :listed_count
    attr_accessor :downloaded_count
    attr_accessor :downloaded_bytes
    attr_accessor :skipped_unsafe_count
    attr_accessor :elapsed_seconds

    attr_reader :destination
    attr_reader :failed

    def initialize(destination:)
      @destination = destination
      @status = :ok
      @failed = {}
      @listed_count = 0
      @downloaded_count = 0
      @downloaded_bytes = 0
      @skipped_unsafe_count = 0
      @elapsed_seconds = 0.0
    end

    def record_downloaded(bytes)
      @downloaded_count += 1
      @downloaded_bytes += bytes.to_i
      nil
    end

    def record_failure(object_name, reason)
      return nil if @failed.size >= FAILURE_SAMPLE_LIMIT

      @failed[object_name] = reason
      nil
    end

    def ok?
      @status == :ok
    end

    def to_log_metadata
      {
        status: status,
        destination: destination.to_s,
        listed_count: listed_count,
        downloaded_count: downloaded_count,
        downloaded_bytes: downloaded_bytes,
        skipped_unsafe_count: skipped_unsafe_count,
        failed_count: failed.size,
        elapsed_seconds: elapsed_seconds
      }
    end
  end
end
