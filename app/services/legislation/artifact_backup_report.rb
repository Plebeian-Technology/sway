# frozen_string_literal: true

module Legislation
  class ArtifactBackupReport
    FAILURE_SAMPLE_LIMIT = 50

    attr_accessor :status
    attr_accessor :listed_count
    attr_accessor :uploaded_count
    attr_accessor :uploaded_bytes
    attr_accessor :skipped_present_count
    attr_accessor :skipped_identical_count
    attr_accessor :skipped_temp_count
    attr_accessor :skipped_vanished_count
    attr_accessor :floor
    attr_accessor :elapsed_seconds

    attr_reader :files_found_by_root
    attr_reader :failed

    def initialize
      @status = :ok
      @files_found_by_root = {}
      @failed = {}
      @listed_count = 0
      @uploaded_count = 0
      @uploaded_bytes = 0
      @skipped_present_count = 0
      @skipped_identical_count = 0
      @skipped_temp_count = 0
      @skipped_vanished_count = 0
      @floor = 0
      @elapsed_seconds = 0.0
    end

    def record_found(root_key)
      @files_found_by_root[root_key] = @files_found_by_root.fetch(root_key, 0) + 1
      nil
    end

    def record_uploaded(bytes)
      @uploaded_count += 1
      @uploaded_bytes += bytes
      nil
    end

    def record_failure(object_name, reason)
      return nil if @failed.size >= FAILURE_SAMPLE_LIMIT

      @failed[object_name] = reason
      nil
    end

    def files_found
      @files_found_by_root.values.sum
    end

    def ok?
      @status == :ok
    end

    def to_log_metadata
      {
        status: status,
        listed_count: listed_count,
        files_found: files_found,
        files_found_by_root: files_found_by_root,
        uploaded_count: uploaded_count,
        uploaded_bytes: uploaded_bytes,
        skipped_present_count: skipped_present_count,
        skipped_identical_count: skipped_identical_count,
        skipped_temp_count: skipped_temp_count,
        skipped_vanished_count: skipped_vanished_count,
        floor: floor,
        failed_count: failed.size,
        elapsed_seconds: elapsed_seconds
      }
    end
  end
end
