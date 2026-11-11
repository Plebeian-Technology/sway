# frozen_string_literal: true

module Eval
  # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the staleness discriminator is a content digest, not a commit sha]]
  # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#What the staleness check does not do]]
  class ManifestStaleness
    class StaleManifestError < StandardError; end

    Result = Data.define(:checked_entries, :builder_content_digest)

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the staleness discriminator is a content digest, not a commit sha]]
    WATCHED_FILES = Eval::PromptDump::WATCHED_BUILDER_FILES

    REDUMP_INSTRUCTION =
      "Re-run `bundle exec rake sway:eval:dump` -- the committed hashes describe bytes " \
      "the builders no longer emit."

    class << self
      def call(manifest_path:)
        new(manifest_path: manifest_path).call
      end
    end

    def initialize(manifest_path:)
      @manifest_path = manifest_path
    end

    def call
      entries = load_entries
      current_digest = Eval::PromptDump.builder_content_digest

      entries.each do |key, entry|
        assert_watch_list!(key, entry)
        assert_digest!(key, entry, current_digest)
      end

      Result.new(checked_entries: entries.size, builder_content_digest: current_digest)
    end

    private

    attr_reader :manifest_path

    def load_entries
      unless manifest_path.exist?
        raise StaleManifestError,
          "Eval::ManifestStaleness: no manifest at #{manifest_path}. #{REDUMP_INSTRUCTION}"
      end

      entries = JSON.parse(manifest_path.read)
      if entries.empty?
        raise StaleManifestError,
          "Eval::ManifestStaleness: #{manifest_path} holds no entries, so comparing it " \
          "would pass while checking nothing. #{REDUMP_INSTRUCTION}"
      end

      entries
    end

    def assert_watch_list!(key, entry)
      recorded = entry["builder_digest_files"]
      return if recorded == WATCHED_FILES

      raise StaleManifestError,
        "Eval::ManifestStaleness: entry #{key} was recorded against a different watch list " \
        "(#{recorded.inspect}) than the one in force (#{WATCHED_FILES.inspect}). A manifest " \
        "recorded against a shorter watch list passes while checking nothing. #{REDUMP_INSTRUCTION}"
    end

    def assert_digest!(key, entry, current_digest)
      return if entry["builder_content_digest"] == current_digest

      raise StaleManifestError,
        "Eval::ManifestStaleness: entry #{key} records builder content digest " \
        "#{entry["builder_content_digest"]}, but the watched files on disk now digest to " \
        "#{current_digest}. Moved: #{moved_files(entry).join(", ")}. #{REDUMP_INSTRUCTION}"
    end

    # @lat: [[lat.md/explanation/eval-prompt-manifest-normalisation#Why the staleness discriminator is a content digest, not a commit sha]]
    def moved_files(entry)
      recorded = entry["builder_file_digests"]
      return WATCHED_FILES.map { |path| "#{path} (entry records no per-file digest)" } if recorded.nil?

      current = Eval::PromptDump.builder_file_digests
      WATCHED_FILES.reject { |path| recorded[path] == current[path] }
    end
  end
end
