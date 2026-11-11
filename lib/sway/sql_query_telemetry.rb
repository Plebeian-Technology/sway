# frozen_string_literal: true

module Sway
  # @lat: [[query-plan-indexes#A query-cost guard measures growth, not a ceiling]]
  module SqlQueryTelemetry
    N_PLUS_ONE_WARN_THRESHOLD = 15
    MAX_SQL_INPUT_LENGTH = 65_536
    MAX_SQL_FINGERPRINT_LENGTH = 4096
    IGNORED_PAYLOAD_NAMES = /\A(?:SCHEMA|TRANSACTION)\z/

    Result = Data.define(
      :queries,
      :cached_queries,
      :max_repeats,
      :top_fingerprint,
      :fingerprints
    )

    def self.fingerprint(sql)
      raw = sql.to_s
      unless raw.encoding == Encoding::UTF_8 && raw.valid_encoding?
        raw = raw.encode(Encoding::UTF_8, invalid: :replace, undef: :replace, replace: "?")
      end
      normalized = (raw[0, MAX_SQL_INPUT_LENGTH] || "").dup
      normalized.gsub!(/\b[xX]'[^']*(?:''[^']*)*(?:'|\z)|'[^']*(?:''[^']*)*(?:'|\z)/, "?")
      normalized.gsub!(/(?<!\w)-?\d+(?:\.\d+)?\b/, "?")
      normalized.gsub!(/\bIN\s*\(\s*\?(?:\s*,\s*\?)+(?:\s*\)|\s*,?\s*\z)/i, "IN (?)")
      normalized.gsub!(/\s+/, " ")
      normalized.strip!
      normalized[0, MAX_SQL_FINGERPRINT_LENGTH] || ""
    end

    def self.measure(on_complete: nil)
      queries = 0
      cached_queries = 0
      fingerprints = Hash.new(0) #: Hash[String, Integer]
      target_thread = Thread.current

      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        next unless Thread.current == target_thread
        next if IGNORED_PAYLOAD_NAMES.match?(payload[:name].to_s)

        if payload[:cached]
          cached_queries += 1
          next
        end

        sql = payload[:sql].to_s
        next if sql.empty?

        queries += 1
        fp = fingerprint(sql)
        fingerprints[fp] = fingerprints.fetch(fp, 0) + 1
      end

      begin
        yield
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
        top_entry = fingerprints.max_by { |_fp, count| count }
        result = Result.new(
          queries: queries,
          cached_queries: cached_queries,
          max_repeats: top_entry ? top_entry[1] : 0,
          top_fingerprint: top_entry ? top_entry[0] : nil,
          fingerprints: fingerprints
        )
        on_complete&.call(result)
      end

      result #: Result
    end
  end
end
