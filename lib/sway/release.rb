# frozen_string_literal: true

require "time"

module Sway
  # @lat: [[release-metadata-values#Per-environment behavior]]
  module Release
    SHORT_SHA_CHARS = 8

    # @lat: [[release-git-fallback-and-caching#Why GIT_TIMEOUT_SECONDS is 10]]
    GIT_TIMEOUT_SECONDS = 10

    class << self
      def version
        raw = ENV["SWAY_RELEASE_VERSION"].to_s.strip
        return nil if raw.empty?

        Integer(raw, exception: false)
      end

      # @lat: [[release-git-fallback-and-caching#Why sha is not memoized]]
      def sha
        ENV["SWAY_RELEASE_SHA"].to_s.strip.then { |s| s.empty? ? git("rev-parse", "HEAD") : s }
      end

      def short_sha
        sha&.slice(0, SHORT_SHA_CHARS)
      end

      def previous_sha
        ENV["SWAY_PREVIOUS_SHA"].to_s.strip.then { |s| s.empty? ? nil : s }
      end

      def previous_short_sha
        previous_sha&.slice(0, SHORT_SHA_CHARS)
      end

      def deployed_at
        raw = ENV["SWAY_DEPLOYED_AT"].to_s.strip
        return nil if raw.empty?

        Time.iso8601(raw)
      rescue ArgumentError
        nil
      end

      # @lat: [[release-git-fallback-and-caching#Why the uncommitted-changes digest is checked at every link of its chain]]
      def uncommitted_digest
        ENV["SWAY_UNCOMMITTED_DIGEST"].to_s.strip.then { |value| value.empty? ? nil : value }
      end

      # @lat: [[release-git-fallback-and-caching#Why built_from_committed_tree? never falls back to git]]
      def built_from_committed_tree?
        raw = ENV["SWAY_UNCOMMITTED_DIGEST"]
        return nil if raw.nil?

        raw.strip.empty?
      end

      # @lat: [[release-git-fallback-and-caching#Why to_sway_json reads sha once]]
      def to_sway_json
        current_sha = sha
        {
          version: version,
          sha: current_sha,
          short_sha: current_sha&.slice(0, SHORT_SHA_CHARS),
          previous_sha: previous_sha,
          previous_short_sha: previous_short_sha,
          deployed_at: deployed_at&.iso8601,
          uncommitted_digest: uncommitted_digest,
          built_from_committed_tree: built_from_committed_tree?
        }
      end

      private

      # @lat: [[release-metadata-values#Per-environment behavior]]
      def git(*args)
        return nil if Rails.env.production?

        out, _err, status = Sway::Subprocess.capture3("git", *args, timeout_seconds: GIT_TIMEOUT_SECONDS)
        return nil unless status.success?

        out.strip.then { |s| s.empty? ? nil : s }
      rescue
        nil
      end
    end
  end
end
