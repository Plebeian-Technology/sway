# frozen_string_literal: true

module Litestream
  # @lat: [[litestream-lag-decision-and-reading-fields#Litestream::LagDecision]]
  class LagDecision < Data.define(
    :outcome,
    :alarm,
    :last_replica_txid,
    :consecutive_stalls,
    :consecutive_read_failures,
    :consecutive_empty_listings,
    :stalled_since,
    :stalled_for_seconds
  )
  end
end
