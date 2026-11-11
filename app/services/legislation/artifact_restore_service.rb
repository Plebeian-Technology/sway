# frozen_string_literal: true

module Legislation
  class ArtifactRestoreService
    class LiveTreeRefused < StandardError; end

    FAILURE_REASON_LENGTH = 200

    def initialize(destination:, bucket: ArtifactBucket.new, prefix: ArtifactBackupService.default_prefix, only: nil, allow_live_tree: false)
      @destination = expand_destination(destination)
      @bucket = bucket
      @prefix = prefix
      @only = normalize_only(only)
      @effective_prefix = @only.nil? ? prefix : "#{prefix}#{@only}/"
      refuse_live_tree! unless allow_live_tree
      @report = ArtifactRestoreReport.new(destination: @destination)
    end

    attr_reader :destination
    attr_reader :effective_prefix

    def call
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      listed = list_remote
      return finish(started_at) if listed.nil?

      listed.each { |file| restore_object(file) }
      finish(started_at)
    end

    private

    attr_reader :bucket
    attr_reader :prefix
    attr_reader :only
    attr_reader :report

    def expand_destination(value)
      given = value.to_s.strip
      raise ArgumentError, "Legislation::ArtifactRestoreService: destination must name a directory" if given.empty?

      resolve_symlinks(Pathname.new(given).expand_path)
    end

    # @lat: [[legislation-artifact-backup#Why the destination is resolved through its symlinks]]
    def resolve_symlinks(path)
      existing = path
      existing = existing.parent while !existing.exist? && !existing.root?
      return path unless existing.exist?
      return existing.realpath if existing == path

      existing.realpath.join(path.relative_path_from(existing))
    end

    def normalize_only(value)
      return nil if value.nil?

      key = value.to_s
      return key if ArtifactBackupService::ROOTS.key?(key)

      raise ArgumentError,
        "Legislation::ArtifactRestoreService: only must be one of #{ArtifactBackupService::ROOTS.keys.join(", ")}, got #{key.inspect}"
    end

    def live_paths
      roots = ArtifactBackupService::ROOTS.values.map { |paths_method| Legislation::Paths.public_send(paths_method) } #: Array[Pathname]
      ([Legislation::Paths.root] + roots).map { |path| resolve_symlinks(path.expand_path) }
    end

    # @lat: [[legislation-artifact-backup#Why the restore destination has no default]]
    def refuse_live_tree!
      clash = live_paths.find { |root| overlaps?(root) }
      return nil if clash.nil?

      raise LiveTreeRefused,
        "Legislation::ArtifactRestoreService refuses to write #{destination}: it overlaps the live artifact tree at #{clash}. " \
        "Restore into a directory outside the tree, or pass allow_live_tree: true to accept overwriting it."
    end

    def overlaps?(root)
      destination == root ||
        destination.to_s.start_with?("#{root}/") ||
        root.to_s.start_with?("#{destination}/")
    end

    def list_remote
      listed = bucket.list(prefix: effective_prefix)
      report.listed_count = listed.size
      listed
    rescue => e
      SwayLogging.log_exception(
        "legislation_artifact_restore.listing_failed",
        exception: e,
        level: :error,
        prefix: effective_prefix
      )
      Sentry.capture_exception(e) if Rails.env.production?
      report.status = :listing_failed
      nil
    end

    def restore_object(file)
      local_path = local_path_for(file.name)

      if local_path.nil?
        report.skipped_unsafe_count += 1
        SwayLogging.warn("legislation_artifact_restore.unsafe_object_name", object_name: file.name, prefix: prefix)
        return nil
      end

      bucket.download(object_name: file.name, local_path: local_path)
      report.record_downloaded(file.size)
      nil
    rescue => e
      report.record_failure(file.name, "#{e.class.name}: #{e.message.to_s[0, FAILURE_REASON_LENGTH]}")
      SwayLogging.log_exception(
        "legislation_artifact_restore.download_failed",
        exception: e,
        level: :warn,
        object_name: file.name
      )
      nil
    end

    # @lat: [[legislation-artifact-backup#Why every object name is checked again before it is written]]
    def local_path_for(object_name)
      return nil unless object_name.start_with?(prefix)

      remainder = object_name.delete_prefix(prefix)
      return nil if remainder.empty?
      return nil if remainder.split("/").include?("..")

      path = Pathname.new(remainder)
      return nil if path.absolute?

      destination.join(path)
    end

    def finish(started_at)
      report.elapsed_seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(3).to_f
      SwayLogging.info("legislation_artifact_restore.finished", **report.to_log_metadata)
      report
    end
  end
end
