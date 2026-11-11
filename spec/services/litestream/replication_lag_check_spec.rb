# frozen_string_literal: true

require "rails_helper"

# @lat: [[replication-lag-check-internals-design#ReplicationLagCheck reads nothing outside itself]]
RSpec.describe Litestream::ReplicationLagCheck do
  def build_decision(
    status:,
    position: nil,
    previous_position: nil,
    consecutive_stalls: 0,
    consecutive_read_failures: 0,
    consecutive_empty_listings: 0,
    stalled_since: nil,
    now: Time.zone.now
  )
    described_class.new(
      status: status,
      position: position,
      previous_position: previous_position,
      consecutive_stalls: consecutive_stalls,
      consecutive_read_failures: consecutive_read_failures,
      consecutive_empty_listings: consecutive_empty_listings,
      stalled_since: stalled_since,
      now: now
    ).call
  end

  it "row 1: the very first run ever records the number and asks for nothing" do
    decision = build_decision(status: :ok, position: 7, previous_position: nil)

    expect(decision.outcome).to eq(:first_run)
    expect(decision.last_replica_txid).to eq(7)
    expect(decision.consecutive_stalls).to eq(0)
    expect(decision.consecutive_read_failures).to eq(0)
    expect(decision.consecutive_empty_listings).to eq(0)
    expect(decision.stalled_since).to be_nil
    expect(decision.alarm).to be(false)
  end

  it "row 2: a number that moved forward is an ordinary healthy run" do
    decision = build_decision(status: :ok, position: 9, previous_position: 7)

    expect(decision.outcome).to eq(:healthy)
    expect(decision.last_replica_txid).to eq(9)
    expect(decision.consecutive_stalls).to eq(0)
    expect(decision.alarm).to be(false)
  end

  it "row 5: a number that has not moved counts the first stall, sets stalled-since to now, and does not alarm" do
    now = Time.zone.now
    decision = build_decision(status: :ok, position: 7, previous_position: 7, consecutive_stalls: 0, now: now)

    expect(decision.outcome).to eq(:stall)
    expect(decision.consecutive_stalls).to eq(1)
    expect(decision.stalled_since).to eq(now)
    expect(decision.alarm).to be(false)
  end

  it "row 6: the second consecutive stall alarms and keeps the stalled-since time it was given" do
    since = 30.minutes.ago
    decision = build_decision(status: :ok, position: 7, previous_position: 7, consecutive_stalls: 1, stalled_since: since)

    expect(decision.outcome).to eq(:stall)
    expect(decision.consecutive_stalls).to eq(2)
    expect(decision.stalled_since).to eq(since)
    expect(decision.alarm).to be(true)
  end

  it "row 7: every stalled run after the second alarms again" do
    since = 45.minutes.ago
    decision = build_decision(status: :ok, position: 7, previous_position: 7, consecutive_stalls: 2, stalled_since: since)

    expect(decision.outcome).to eq(:stall)
    expect(decision.consecutive_stalls).to eq(3)
    expect(decision.stalled_since).to eq(since)
    expect(decision.alarm).to be(true)
  end

  it "row 8: a reading lower than the stored number is a stall, and the stored number is kept" do
    decision = build_decision(status: :ok, position: 7, previous_position: 9)

    expect(decision.outcome).to eq(:stall)
    expect(decision.last_replica_txid).to eq(9)
    expect(decision.consecutive_stalls).to eq(1)
  end

  it "a stall resets the read-failure and empty-listing counters, because the listing worked and was not empty" do
    decision = build_decision(
      status: :ok,
      position: 7,
      previous_position: 7,
      consecutive_read_failures: 3,
      consecutive_empty_listings: 2
    )

    expect(decision.outcome).to eq(:stall)
    expect(decision.consecutive_read_failures).to eq(0)
    expect(decision.consecutive_empty_listings).to eq(0)
  end

  it "row 3: the flip back to healthy after one stall reports how long the copy was stopped" do
    now = Time.zone.now
    since = now - 1.hour
    decision = build_decision(status: :ok, position: 9, previous_position: 7, consecutive_stalls: 1, stalled_since: since, now: now)

    expect(decision.outcome).to eq(:recovered)
    expect(decision.consecutive_stalls).to eq(0)
    expect(decision.stalled_since).to be_nil
    expect(decision.stalled_for_seconds).to eq(3600)
    expect(decision.alarm).to be(false)
  end

  it "row 4: a recovery after several stalls is still exactly one recovery outcome, not three" do
    now = Time.zone.now
    since = now - 1.hour
    decision = build_decision(status: :ok, position: 9, previous_position: 7, consecutive_stalls: 3, stalled_since: since, now: now)

    expect(decision.outcome).to eq(:recovered)
    expect(decision.consecutive_stalls).to eq(0)
    expect(decision.stalled_for_seconds).to eq(3600)
  end

  it "the run after a recovery is an ordinary healthy run, so an ordinary healthy run never produces the recovery message" do
    decision = build_decision(status: :ok, position: 11, previous_position: 9, consecutive_stalls: 0, stalled_since: nil)

    expect(decision.outcome).to eq(:healthy)
    expect(decision.stalled_for_seconds).to be_nil
  end

  it "a recovery also resets the read-failure and empty-listing counters, because the listing worked and was not empty" do
    now = Time.zone.now
    decision = build_decision(
      status: :ok,
      position: 9,
      previous_position: 7,
      consecutive_stalls: 1,
      stalled_since: now - 1.hour,
      consecutive_read_failures: 2,
      consecutive_empty_listings: 1,
      now: now
    )

    expect(decision.outcome).to eq(:recovered)
    expect(decision.consecutive_read_failures).to eq(0)
    expect(decision.consecutive_empty_listings).to eq(0)
  end

  it "reports the outage length as absent rather than raising when a stall count arrived with no stalled-since time" do
    decision = build_decision(status: :ok, position: 9, previous_position: 7, consecutive_stalls: 1, stalled_since: nil)

    expect(decision.outcome).to eq(:recovered)
    expect(decision.stalled_for_seconds).to be_nil
  end

  it "row 9: a failed read leaves the stall count, the stored number and the stalled-since time untouched" do
    since = 10.minutes.ago
    decision = build_decision(status: :unreadable, previous_position: 7, consecutive_stalls: 1, stalled_since: since)

    expect(decision.outcome).to eq(:read_failure)
    expect(decision.consecutive_stalls).to eq(1)
    expect(decision.last_replica_txid).to eq(7)
    expect(decision.stalled_since).to eq(since)
    expect(decision.consecutive_read_failures).to eq(1)
    expect(decision.consecutive_empty_listings).to eq(0)
    expect(decision.alarm).to be(false)
  end

  it "a second consecutive failed read alarms" do
    decision = build_decision(status: :unreadable, previous_position: 7, consecutive_read_failures: 1)

    expect(decision.outcome).to eq(:read_failure)
    expect(decision.consecutive_read_failures).to eq(2)
    expect(decision.alarm).to be(true)
  end

  it "row 10: an empty listing leaves the stall count and the stored number untouched, and counts on its own counter" do
    decision = build_decision(status: :empty, previous_position: 7, consecutive_stalls: 1)

    expect(decision.outcome).to eq(:empty_listing)
    expect(decision.consecutive_stalls).to eq(1)
    expect(decision.last_replica_txid).to eq(7)
    expect(decision.consecutive_empty_listings).to eq(1)
    expect(decision.consecutive_read_failures).to eq(0)
    expect(decision.alarm).to be(false)
  end

  it "a second consecutive empty listing alarms" do
    decision = build_decision(status: :empty, previous_position: 7, consecutive_empty_listings: 1)

    expect(decision.outcome).to eq(:empty_listing)
    expect(decision.consecutive_empty_listings).to eq(2)
    expect(decision.alarm).to be(true)
  end

  it "row 11: an empty listing with no previous number at all counts on the empty-listing counter, never the stall counter" do
    decision = build_decision(status: :empty, previous_position: nil)

    expect(decision.outcome).to eq(:empty_listing)
    expect(decision.consecutive_stalls).to eq(0)
    expect(decision.consecutive_empty_listings).to eq(1)
    expect(decision.last_replica_txid).to be_nil
  end

  it "row 12: a failed read with no previous number at all counts on the read-failure counter, never the stall counter" do
    decision = build_decision(status: :unreadable, previous_position: nil)

    expect(decision.outcome).to eq(:read_failure)
    expect(decision.consecutive_stalls).to eq(0)
    expect(decision.consecutive_read_failures).to eq(1)
    expect(decision.last_replica_txid).to be_nil
  end

  it "stall, then a failed read, then another stall still reaches two consecutive stalls and alarms" do
    first = build_decision(status: :ok, position: 7, previous_position: 7)
    expect(first.consecutive_stalls).to eq(1)
    expect(first.alarm).to be(false)

    second = build_decision(
      status: :unreadable,
      previous_position: first.last_replica_txid,
      consecutive_stalls: first.consecutive_stalls,
      consecutive_read_failures: first.consecutive_read_failures,
      consecutive_empty_listings: first.consecutive_empty_listings,
      stalled_since: first.stalled_since
    )
    expect(second.consecutive_stalls).to eq(1)
    expect(second.alarm).to be(false)

    third = build_decision(
      status: :ok,
      position: 7,
      previous_position: second.last_replica_txid,
      consecutive_stalls: second.consecutive_stalls,
      consecutive_read_failures: second.consecutive_read_failures,
      consecutive_empty_listings: second.consecutive_empty_listings,
      stalled_since: second.stalled_since
    )
    expect(third.consecutive_stalls).to eq(2)
    expect(third.alarm).to be(true)
  end

  it "a failed read, then an empty listing, then another failed read still reaches two consecutive read failures and alarms" do
    first = build_decision(status: :unreadable, previous_position: 7)
    expect(first.consecutive_read_failures).to eq(1)
    expect(first.alarm).to be(false)

    second = build_decision(
      status: :empty,
      previous_position: first.last_replica_txid,
      consecutive_stalls: first.consecutive_stalls,
      consecutive_read_failures: first.consecutive_read_failures,
      consecutive_empty_listings: first.consecutive_empty_listings,
      stalled_since: first.stalled_since
    )
    expect(second.consecutive_read_failures).to eq(1)
    expect(second.alarm).to be(false)

    third = build_decision(
      status: :unreadable,
      previous_position: second.last_replica_txid,
      consecutive_stalls: second.consecutive_stalls,
      consecutive_read_failures: second.consecutive_read_failures,
      consecutive_empty_listings: second.consecutive_empty_listings,
      stalled_since: second.stalled_since
    )
    expect(third.consecutive_read_failures).to eq(2)
    expect(third.alarm).to be(true)
  end

  it "a successful non-empty listing resets both the read-failure and the empty-listing counters" do
    decision = build_decision(
      status: :ok,
      position: 9,
      previous_position: 7,
      consecutive_read_failures: 1,
      consecutive_empty_listings: 1
    )

    expect(decision.consecutive_read_failures).to eq(0)
    expect(decision.consecutive_empty_listings).to eq(0)
  end

  # @lat: [[replication-lag-check#A promise the type system cannot hold is closed by a raise]]
  it "refuses an unrecognized status" do
    bad_status = :nonsense #: untyped

    expect { build_decision(status: bad_status, position: 7, previous_position: 7) }
      .to raise_error(ArgumentError, "Litestream::ReplicationLagCheck#status must be :ok, :empty or :unreadable")
  end

  # @lat: [[replication-lag-check#A promise the type system cannot hold is closed by a raise]]
  it "refuses status :ok carrying no position" do
    expect { build_decision(status: :ok, position: nil, previous_position: 7) }
      .to raise_error(ArgumentError, "Litestream::ReplicationLagCheck#position must be present when status is :ok")
  end
end
