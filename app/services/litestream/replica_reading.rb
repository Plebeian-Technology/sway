# frozen_string_literal: true

module Litestream
  # @lat: [[litestream-lag-decision-and-reading-fields#Litestream::ReplicaReading]]
  class ReplicaReading < Data.define(:status, :position, :bucket_name, :path, :error)
    STATUSES = %i[ok empty unreadable].freeze

    def initialize(status:, position:, bucket_name:, path:, error:)
      unless STATUSES.include?(status)
        raise ArgumentError, "Litestream::ReplicaReading#status must be one of #{STATUSES.inspect} (got #{status.inspect})"
      end

      super
    end
  end
end
