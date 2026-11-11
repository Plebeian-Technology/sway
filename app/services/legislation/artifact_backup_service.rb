# frozen_string_literal: true

module Legislation
  class ArtifactBackupService
    # @lat: [[legislation-artifact-backup#Why the walk asks the paths helper for each root]]
    ROOT_KEY_BILLS_TEXT = "bills/text"

    ROOTS = {
      "bills/raw" => :bills_raw,
      ROOT_KEY_BILLS_TEXT => :bills_text,
      "hearings" => :hearings,
      "law" => :law,
      "diffs" => :diffs,
      "prompt_dumps" => :prompt_dumps,
      "attachments" => :attachments
    }.freeze

    # @lat: [[legislation-artifact-backup#Why the walk ignores the atomic-write temporary files]]
    TEMP_FILE_PATTERN = /\A\..+\.tmp-\d+-[0-9a-f]+\z/

    FAILURE_REASON_LENGTH = 200

    def self.default_prefix
      "legislation/#{Rails.env}/"
    end

    def initialize(bucket: ArtifactBucket.new, prefix: self.class.default_prefix)
      @bucket = bucket
      @prefix = prefix
      @report = ArtifactBackupReport.new
    end

    def call
      started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      remote = list_remote
      return finish(started_at) if remote.nil?

      candidates = collect_candidates(remote)
      return finish(started_at) unless floor_met?

      upload_candidates(candidates)
      finish(started_at)
    end

    private

    attr_reader :bucket
    attr_reader :prefix
    attr_reader :report

    # @lat: [[legislation-artifact-backup#Why the bucket is listed once and a failed listing stops the run]]
    def list_remote
      listed = bucket.list(prefix: prefix)
      index = {} #: Hash[String, SwayGoogleCloudStorage::ListedFile]
      listed.each { |file| index[file.name] = file }
      report.listed_count = listed.size
      index
    rescue => e
      SwayLogging.log_exception(
        "legislation_artifact_backup.listing_failed",
        exception: e,
        level: :error,
        prefix: prefix
      )
      Sentry.capture_exception(e) if Rails.env.production?
      report.status = :listing_failed
      nil
    end

    def collect_candidates(remote)
      seen = Set.new #: Set[Pathname]
      candidates = [] #: Array[candidate]

      ROOTS.each do |root_key, paths_method|
        root = Legislation::Paths.public_send(paths_method) #: Pathname
        next unless root.directory?

        Pathname.glob(root.join("**", "*").to_s, File::FNM_DOTMATCH).each do |entry|
          collect_entry(entry, root: root, root_key: root_key, remote: remote, seen: seen, candidates: candidates)
        end
      end

      candidates
    end

    # @lat: [[legislation-artifact-backup#Why a file that vanishes mid-walk does not stop the run]]
    def collect_entry(entry, root:, root_key:, remote:, seen:, candidates:)
      return if entry.symlink?

      if TEMP_FILE_PATTERN.match?(entry.basename.to_s)
        report.skipped_temp_count += 1
        return
      end

      return unless entry.file?
      return unless seen.add?(entry.realpath)

      relative = entry.relative_path_from(root).to_s
      return if relative.start_with?("..")

      report.record_found(root_key)
      object_name = "#{prefix}#{root_key}/#{relative}"
      size = entry.size

      case freshness(remote[object_name], entry, size)
      when :present
        report.skipped_present_count += 1
        return
      when :identical
        report.skipped_identical_count += 1
        return
      end

      candidates << [object_name, entry, size]
      nil
    rescue SystemCallError
      report.skipped_vanished_count += 1
      nil
    end

    # @lat: [[legislation-artifact-backup#Why a file whose size matches is copied again when the local one is newer]]
    def freshness(listed, entry, size)
      return :stale if listed.nil?
      return :stale if listed.size != size

      remote_md5 = listed.md5
      return modified_since_stored?(listed, entry) ? :stale : :present if remote_md5.nil?

      identical?(remote_md5, entry) ? :identical : :stale
    end

    # @lat: [[legislation-artifact-backup#Why a rewrite with identical bytes is not copied again]]
    def identical?(remote_md5, entry)
      Digest::MD5.file(entry.to_s).base64digest == remote_md5
    end

    def modified_since_stored?(listed, entry)
      created_at = listed.created_at
      created_at.nil? || entry.mtime > created_at
    end

    # @lat: [[legislation-artifact-backup#Why a run checks what it found against a floor taken from the database]]
    def floor_met?
      report.floor = ArtifactFloor.bills_text_floor
      return true unless report.floor.positive?

      found = report.files_found_by_root.fetch(ROOT_KEY_BILLS_TEXT, 0)
      return true if found >= report.floor

      SwayLogging.error(
        "legislation_artifact_backup.floor_not_met",
        files_found: report.files_found,
        bills_text_found: found,
        floor: report.floor,
        bills_text_root: Legislation::Paths.bills_text.to_s
      )
      if Rails.env.production?
        Sentry.capture_message(
          "Legislation artifact backup found #{found} files under bills/text where at least #{report.floor} were expected",
          level: :error
        )
      end
      report.status = :floor_not_met
      false
    end

    def upload_candidates(candidates)
      candidates.each do |object_name, path, size|
        bucket.upload(object_name: object_name, local_path: path)
        report.record_uploaded(size)
      rescue => e
        report.record_failure(object_name, "#{e.class.name}: #{e.message.to_s[0, FAILURE_REASON_LENGTH]}")
        SwayLogging.log_exception(
          "legislation_artifact_backup.upload_failed",
          exception: e,
          level: :warn,
          object_name: object_name
        )
      end
      nil
    end

    def finish(started_at)
      report.elapsed_seconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at).round(3).to_f
      SwayLogging.info("legislation_artifact_backup.finished", **report.to_log_metadata)
      report
    end
  end
end
