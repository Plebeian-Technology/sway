# frozen_string_literal: true

module Litestream
  # @lat: [[replication-lag-check-internals-design#ReplicationLagCheck reads nothing outside itself]]
  class ReplicationLagCheck
    # @lat: [[replication-lag-check-internals-design#ReplicationLagCheck reads nothing outside itself]]
    FORGIVENESS_THRESHOLD = 2

    def initialize(status:, position:, previous_position:, consecutive_stalls:, consecutive_read_failures:, consecutive_empty_listings:, stalled_since:, now:)
      @status = status
      @position = position
      @previous_position = previous_position
      @consecutive_stalls = consecutive_stalls
      @consecutive_read_failures = consecutive_read_failures
      @consecutive_empty_listings = consecutive_empty_listings
      @stalled_since = stalled_since
      @now = now
    end

    def call
      case status
      when :ok
        ok_decision
      when :unreadable
        read_failure_decision
      when :empty
        empty_listing_decision
      else
        # @lat: [[replication-lag-check#A promise the type system cannot hold is closed by a raise]]
        raise ArgumentError, "Litestream::ReplicationLagCheck#status must be :ok, :empty or :unreadable"
      end
    end

    private

    attr_reader :status, :position, :previous_position, :consecutive_stalls,
      :consecutive_read_failures, :consecutive_empty_listings, :stalled_since, :now

    # @lat: [[replication-lag-check-internals-design#ok_decision: the first run, a stall, or progress]]
    def ok_decision
      current_position = required_position

      return first_run_decision(current_position) if previous_position.nil?

      if current_position > previous_position
        moved_decision(current_position)
      else
        stall_decision(previous_position)
      end
    end

    # @lat: [[replication-lag-check-internals-design#ReplicationLagCheck reads nothing outside itself]]
    def required_position
      raise ArgumentError, "Litestream::ReplicationLagCheck#position must be present when status is :ok" if position.nil?

      position #: Integer
    end

    # @lat: [[replication-lag-check-internals-design#ReplicationLagCheck reads nothing outside itself]]
    def moved_decision(current_position)
      if consecutive_stalls >= 1
        recovered_decision(current_position)
      else
        healthy_decision(current_position)
      end
    end

    def healthy_decision(current_position)
      Litestream::LagDecision.new(
        outcome: :healthy,
        alarm: false,
        last_replica_txid: current_position,
        consecutive_stalls: 0,
        consecutive_read_failures: 0,
        consecutive_empty_listings: 0,
        stalled_since: nil,
        stalled_for_seconds: nil
      )
    end

    def recovered_decision(current_position)
      Litestream::LagDecision.new(
        outcome: :recovered,
        alarm: false,
        last_replica_txid: current_position,
        consecutive_stalls: 0,
        consecutive_read_failures: 0,
        consecutive_empty_listings: 0,
        stalled_since: nil,
        stalled_for_seconds: recovered_outage_seconds
      )
    end

    # @lat: [[replication-lag-check-internals-design#Why stalled_since is measured from a timestamp, not the stall count]]
    def recovered_outage_seconds
      since = stalled_since
      return nil if since.nil?

      (now - since).round
    end

    def first_run_decision(current_position)
      Litestream::LagDecision.new(
        outcome: :first_run,
        alarm: false,
        last_replica_txid: current_position,
        consecutive_stalls: 0,
        consecutive_read_failures: 0,
        consecutive_empty_listings: 0,
        stalled_since: nil,
        stalled_for_seconds: nil
      )
    end

    def stall_decision(stored_position)
      new_stalls = consecutive_stalls + 1

      Litestream::LagDecision.new(
        outcome: :stall,
        alarm: new_stalls >= FORGIVENESS_THRESHOLD,
        last_replica_txid: stored_position,
        consecutive_stalls: new_stalls,
        consecutive_read_failures: 0,
        consecutive_empty_listings: 0,
        # @lat: [[replication-lag-check-internals-design#Why stalled_since is measured from a timestamp, not the stall count]]
        stalled_since: consecutive_stalls.zero? ? now : stalled_since,
        stalled_for_seconds: nil
      )
    end

    # @lat: [[replication-lag-check-internals-design#ReplicationLagCheck reads nothing outside itself]]
    def read_failure_decision
      new_failures = consecutive_read_failures + 1

      Litestream::LagDecision.new(
        outcome: :read_failure,
        alarm: new_failures >= FORGIVENESS_THRESHOLD,
        last_replica_txid: previous_position,
        consecutive_stalls: consecutive_stalls,
        consecutive_read_failures: new_failures,
        consecutive_empty_listings: consecutive_empty_listings,
        stalled_since: stalled_since,
        stalled_for_seconds: nil
      )
    end

    # @lat: [[replication-lag-check-internals-design#ReplicationLagCheck reads nothing outside itself]]
    def empty_listing_decision
      new_empties = consecutive_empty_listings + 1

      Litestream::LagDecision.new(
        outcome: :empty_listing,
        alarm: new_empties >= FORGIVENESS_THRESHOLD,
        last_replica_txid: previous_position,
        consecutive_stalls: consecutive_stalls,
        consecutive_read_failures: consecutive_read_failures,
        consecutive_empty_listings: new_empties,
        stalled_since: stalled_since,
        stalled_for_seconds: nil
      )
    end
  end
end
