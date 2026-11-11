# frozen_string_literal: true

require "rails_helper"

# @lat: [[replication-lag-check-job-design#Why the spec stubs only Litestream::ReplicaPosition.object_names]]
RSpec.describe ReplicationLagCheckJob do
  include ActiveSupport::Testing::TimeHelpers

  # Litestream::ReplicaPosition.new is stubbed to always hand back the same
  # instance, the way spec/jobs/backup_database_job_spec.rb stubs
  # DatabaseBackupService.new — the job builds a fresh reader on every call to
  # #perform, so the stub has to survive more than one call within an example.
  def stub_object_names(names)
    reader = Litestream::ReplicaPosition.new
    allow(Litestream::ReplicaPosition).to receive(:new).and_return(reader)
    allow(reader).to receive(:object_names).and_return(names)
    reader
  end

  def stub_object_names_raising(error)
    reader = Litestream::ReplicaPosition.new
    allow(Litestream::ReplicaPosition).to receive(:new).and_return(reader)
    allow(reader).to receive(:object_names).and_raise(error)
    reader
  end

  before do
    ReplicationHeartbeat.delete_all
  end

  it "stores the highest segment number, even when it lives at a higher level than anything at level 0" do
    stub_object_names(
      [
        "litestream/test/ltx/0/0000000000000001-000000000000000a.ltx",
        "litestream/test/ltx/1/000000000000000b-0000000000000014.ltx"
      ]
    )

    described_class.new.perform

    expect(ReplicationHeartbeat.singleton.last_replica_txid).to eq(0x14)
  end

  it "ignores an object name that does not match the expected shape, without raising" do
    stub_object_names(
      [
        "litestream/test/ltx/0/not-a-segment.txt",
        "litestream/test/ltx/0/0000000000000001-0000000000000005.ltx"
      ]
    )

    expect { described_class.new.perform }.not_to raise_error
    expect(ReplicationHeartbeat.singleton.last_replica_txid).to eq(5)
  end

  it "leaves the stored number alone when the listing comes back empty, and marks the reading empty rather than stalled" do
    ReplicationHeartbeat.singleton.update_columns(last_replica_txid: 7)
    reader = stub_object_names([])

    described_class.new.perform

    expect(ReplicationHeartbeat.singleton.last_replica_txid).to eq(7)
    expect(reader.call.status).to eq(:empty)
  end

  it "leaves the stored number alone when the listing cannot be read, and carries the real error" do
    ReplicationHeartbeat.singleton.update_columns(last_replica_txid: 7)
    error = StandardError.new("listing failed")
    reader = stub_object_names_raising(error)

    described_class.new.perform

    expect(ReplicationHeartbeat.singleton.last_replica_txid).to eq(7)
    expect(reader.call.error).to eq(error)
    expect(reader.call.status).to eq(:unreadable)
  end

  it "records the number it read on the very first run ever, with nothing stored yet" do
    expect(ReplicationHeartbeat.singleton.last_replica_txid).to be_nil
    stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000003.ltx"])

    described_class.new.perform

    expect(ReplicationHeartbeat.singleton.last_replica_txid).to eq(3)
  end

  it "issues an UPDATE on every run, even when nothing else changed" do
    ReplicationHeartbeat.singleton # the row must exist before time is frozen
    stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000003.ltx"])

    travel_to Time.zone.parse("2026-08-13 12:00:00") do
      statements = [] #: Array[String]
      ActiveSupport::Notifications.subscribed(
        ->(*, payload) { statements << payload[:sql] },
        "sql.active_record"
      ) do
        described_class.new.perform
        described_class.new.perform
      end

      updates = statements.grep(/UPDATE "replication_heartbeats"/i)
      expect(updates.size).to eq(2)
    end
  end

  # @lat: [[replication-lag-check-job-design#Reader, decision, sender]]
  describe "the decision's full write onto the heartbeat row" do
    it "writes all six behaviour columns onto the heartbeat after a stalled run" do
      ReplicationHeartbeat.singleton.update_columns(last_replica_txid: 5)
      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000005.ltx"])

      travel_to Time.zone.parse("2026-08-13 12:00:00") do
        described_class.new.perform
      end

      heartbeat = ReplicationHeartbeat.singleton
      expect(heartbeat.last_replica_txid).to eq(5)
      expect(heartbeat.consecutive_stalls).to eq(1)
      expect(heartbeat.consecutive_read_failures).to eq(0)
      expect(heartbeat.consecutive_empty_listings).to eq(0)
      expect(heartbeat.stalled_since).to eq(Time.zone.parse("2026-08-13 12:00:00"))
      expect(heartbeat.checked_at).to eq(Time.zone.parse("2026-08-13 12:00:00"))
    end

    it "leaves the stored number, the stall count and the stalled-since time unchanged on a read failure, while checked_at still moves" do
      stalled_since = Time.zone.parse("2026-08-13 11:00:00")
      ReplicationHeartbeat.singleton.update_columns(
        last_replica_txid: 5,
        consecutive_stalls: 1,
        stalled_since: stalled_since
      )
      stub_object_names_raising(StandardError.new("listing failed"))

      travel_to Time.zone.parse("2026-08-13 12:00:00") do
        described_class.new.perform
      end

      heartbeat = ReplicationHeartbeat.singleton
      expect(heartbeat.last_replica_txid).to eq(5)
      expect(heartbeat.consecutive_stalls).to eq(1)
      expect(heartbeat.stalled_since).to eq(stalled_since)
      expect(heartbeat.consecutive_read_failures).to eq(1)
      expect(heartbeat.checked_at).to eq(Time.zone.parse("2026-08-13 12:00:00"))
    end

    it "clears the stalled-since time on the run where the copy starts moving again" do
      stalled_since = Time.zone.parse("2026-08-13 11:00:00")
      ReplicationHeartbeat.singleton.update_columns(
        last_replica_txid: 5,
        consecutive_stalls: 2,
        stalled_since: stalled_since
      )
      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000006.ltx"])

      described_class.new.perform

      heartbeat = ReplicationHeartbeat.singleton
      expect(heartbeat.last_replica_txid).to eq(6)
      expect(heartbeat.consecutive_stalls).to eq(0)
      expect(heartbeat.stalled_since).to be_nil
    end
  end

  # @lat: [[replication-lag-check-job-design#The check-in margin is minutes, not slots or runs]]
  describe "the stall alarm and the recovery message" do
    before do
      allow(Sentry).to receive(:capture_message)
      allow(Sentry).to receive(:capture_exception)
    end

    it "sends nothing to Sentry on the very first run ever" do
      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000005.ltx"])

      described_class.new.perform

      expect(Sentry).not_to have_received(:capture_message)
    end

    it "sends nothing to Sentry on an ordinary healthy run" do
      ReplicationHeartbeat.singleton.update_columns(last_replica_txid: 5)
      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000006.ltx"])

      described_class.new.perform

      expect(Sentry).not_to have_received(:capture_message)
    end

    it "sends nothing on the first stall — one is forgiven" do
      ReplicationHeartbeat.singleton.update_columns(last_replica_txid: 5)
      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000005.ltx"])

      described_class.new.perform

      expect(Sentry).not_to have_received(:capture_message)
    end

    it "sends the exact stall constant at error level on the second consecutive stall" do
      ReplicationHeartbeat.singleton.update_columns(
        last_replica_txid: 5,
        consecutive_stalls: 1,
        stalled_since: Time.zone.parse("2026-08-13 11:45:00")
      )
      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000005.ltx"])

      described_class.new.perform

      expect(Sentry).to have_received(:capture_message)
        .with(described_class::STALL_ALARM, level: :error, extra: hash_including(consecutive_stalls: 2))
    end

    it "sends the same stall text again on the third consecutive stall, so Sentry folds them into one issue" do
      ReplicationHeartbeat.singleton.update_columns(
        last_replica_txid: 5,
        consecutive_stalls: 2,
        stalled_since: Time.zone.parse("2026-08-13 11:30:00")
      )
      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000005.ltx"])

      described_class.new.perform

      expect(Sentry).to have_received(:capture_message)
        .with(described_class::STALL_ALARM, level: :error, extra: hash_including(consecutive_stalls: 3))
    end

    it "sends one info-level recovery message with the outage length when the copy starts moving again" do
      stalled_since = Time.zone.parse("2026-08-13 11:00:00")
      ReplicationHeartbeat.singleton.update_columns(
        last_replica_txid: 5,
        consecutive_stalls: 3,
        stalled_since: stalled_since
      )
      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000006.ltx"])

      travel_to Time.zone.parse("2026-08-13 12:00:00") do
        described_class.new.perform
      end

      expect(Sentry).to have_received(:capture_message)
        .with(described_class::RECOVERY_MESSAGE, level: :info, extra: hash_including(stalled_for_seconds: 3600))
    end

    it "sends nothing on the ordinary healthy run right after a recovery" do
      stalled_since = Time.zone.parse("2026-08-13 11:00:00")
      ReplicationHeartbeat.singleton.update_columns(
        last_replica_txid: 5,
        consecutive_stalls: 3,
        stalled_since: stalled_since
      )
      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000006.ltx"])
      described_class.new.perform # recovery

      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000007.ltx"])
      described_class.new.perform # ordinary healthy run

      expect(Sentry).to have_received(:capture_message).once
    end

    it "keeps the stall constant and the recovery constant frozen and naming the restore document" do
      expect(described_class::STALL_ALARM).to be_frozen
      expect(described_class::RECOVERY_MESSAGE).to be_frozen
      expect(described_class::STALL_ALARM).to include("docs/litestream-restore.md")
    end

    # frozen_string_literal freezes a plain literal but NOT one with #{...} —
    # interpolation builds a new String at runtime. This catches anyone adding
    # interpolation to an alarm and breaking Sentry's issue grouping.
    it "keeps all four alarm strings frozen, including the two not covered above" do
      expect(described_class::READ_FAILURE_ALARM).to be_frozen
      expect(described_class::EMPTY_LISTING_ALARM).to be_frozen
    end
  end

  # This job reports only through the installed Sentry gem, never
  # straight to Sentry's HTTP Web API. A direct call would need its own
  # secret and could fail silently inside the one job meant to catch silence.
  it "never talks to Sentry's HTTP Web API directly, only through the installed gem" do
    source = Rails.root.join("app", "jobs", "replication_lag_check_job.rb").read

    expect(source).not_to match(/Net::HTTP/)
    expect(source).not_to match(%r{/issues/})
  end

  # @lat: [[replication-lag-check-job-design#What the read-failure and empty-listing examples cover]]
  describe "the read-failure alarm and the empty-listing alarm" do
    before do
      allow(Sentry).to receive(:capture_message)
      allow(Sentry).to receive(:capture_exception)
    end

    it "sends nothing on one read failure" do
      stub_object_names_raising(StandardError.new("listing failed"))

      described_class.new.perform

      expect(Sentry).not_to have_received(:capture_exception)
    end

    it "sends exactly one exception capture on the second consecutive read failure, with the same error the listing raised" do
      error = StandardError.new("listing failed")
      ReplicationHeartbeat.singleton.update_columns(consecutive_read_failures: 1)
      stub_object_names_raising(error)

      described_class.new.perform

      expect(Sentry).to have_received(:capture_exception).once
      expect(Sentry).to have_received(:capture_exception) do |captured, **_options|
        expect(captured.class).to eq(error.class)
        expect(captured.message).to eq(error.message)
      end
    end

    it "sends no message capture on a read failure — the stall text must never appear for a fault on Sway's own side" do
      ReplicationHeartbeat.singleton.update_columns(consecutive_read_failures: 1)
      stub_object_names_raising(StandardError.new("listing failed"))

      described_class.new.perform

      expect(Sentry).not_to have_received(:capture_message)
    end

    it "carries the read-failure count, the bucket and the path in the exception capture's structured fields" do
      ReplicationHeartbeat.singleton.update_columns(consecutive_read_failures: 1)
      stub_object_names_raising(StandardError.new("listing failed"))

      described_class.new.perform

      expect(Sentry).to have_received(:capture_exception)
        .with(anything, hash_including(extra: hash_including(consecutive_read_failures: 2, bucket_name: "sway-test-sqlite", path: "litestream/test")))
    end

    it "sends the exact read-failure alarm text so the runbook's words are searchable against the event" do
      ReplicationHeartbeat.singleton.update_columns(consecutive_read_failures: 1)
      stub_object_names_raising(StandardError.new("listing failed"))

      described_class.new.perform

      expect(Sentry).to have_received(:capture_exception)
        .with(anything, hash_including(extra: hash_including(alarm: described_class::READ_FAILURE_ALARM)))
    end

    # @lat: [[replication-lag-check#A promise the type system cannot hold is closed by a raise]]
    it "refuses to report a read failure when the reading carries no error" do
      ReplicationHeartbeat.singleton.update_columns(consecutive_read_failures: 1)
      reader = Litestream::ReplicaPosition.new
      allow(Litestream::ReplicaPosition).to receive(:new).and_return(reader)
      allow(reader).to receive(:call).and_return(
        Litestream::ReplicaReading.new(status: :unreadable, position: nil, bucket_name: "sway-test-sqlite", path: "litestream/test", error: nil)
      )

      expect { described_class.new.perform }.to raise_error(ArgumentError, /requires an error on the reading/)
    end

    it "groups every read failure into one Sentry issue with a fixed fingerprint" do
      ReplicationHeartbeat.singleton.update_columns(consecutive_read_failures: 1)
      stub_object_names_raising(StandardError.new("listing failed"))

      described_class.new.perform

      expect(Sentry).to have_received(:capture_exception)
        .with(anything, hash_including(fingerprint: ["litestream-read-failure"]))
    end

    it "sends nothing on one empty listing" do
      stub_object_names([])

      described_class.new.perform

      expect(Sentry).not_to have_received(:capture_message)
    end

    it "sends the exact empty-listing constant at error level on the second consecutive empty listing, with the bucket and path in the structured fields" do
      ReplicationHeartbeat.singleton.update_columns(consecutive_empty_listings: 1)
      stub_object_names([])

      described_class.new.perform

      expect(Sentry).to have_received(:capture_message)
        .with(described_class::EMPTY_LISTING_ALARM, level: :error, extra: hash_including(consecutive_empty_listings: 2, bucket_name: "sway-test-sqlite", path: "litestream/test"))
    end

    it "reports the path the reading actually used, not the default, when SWAY_LITESTREAM_PATH differs from the test default" do
      with_env("SWAY_LITESTREAM_PATH" => "litestream/a-different-path") do
        ReplicationHeartbeat.singleton.update_columns(consecutive_empty_listings: 1)
        stub_object_names([])

        described_class.new.perform

        expect(Sentry).to have_received(:capture_message)
          .with(described_class::EMPTY_LISTING_ALARM, level: :error, extra: hash_including(path: "litestream/a-different-path"))
      end
    end

    it "walks stall, read failure, stall and sends the stall alarm once at the end with no read-failure capture" do
      ReplicationHeartbeat.singleton.update_columns(last_replica_txid: 5)

      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000005.ltx"])
      described_class.new.perform # stall 1, forgiven

      stub_object_names_raising(StandardError.new("blip"))
      described_class.new.perform # read failure 1, forgiven

      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000005.ltx"])
      described_class.new.perform # stall 2, alarms

      expect(Sentry).to have_received(:capture_message)
        .with(described_class::STALL_ALARM, level: :error, extra: hash_including(consecutive_stalls: 2)).once
      expect(Sentry).not_to have_received(:capture_exception)
    end
  end

  # @lat: [[replication-lag-check-job-design#Why the cron-monitor examples drive the job with perform_now, not .new.perform]]
  describe "the Sentry cron monitor" do
    def stub_reader_call_raising(error)
      reader = Litestream::ReplicaPosition.new
      allow(Litestream::ReplicaPosition).to receive(:new).and_return(reader)
      allow(reader).to receive(:call).and_raise(error)
      reader
    end

    before do
      allow(Sentry).to receive(:capture_check_in).and_return("check-in-id")
      allow(Sentry).to receive(:capture_message)
      allow(Sentry).to receive(:capture_exception)
    end

    it "sets an explicit monitor slug, different from the value the library would derive from the class name" do
      derived_slug = described_class.name.gsub("::", "-").downcase

      expect(described_class.sentry_monitor_slug).to eq("replication-lag-check")
      expect(described_class.sentry_monitor_slug).not_to eq(derived_slug)
    end

    it "keeps the slug at 50 characters or fewer" do
      expect(described_class.sentry_monitor_slug.length).to be <= 50
    end

    it "sets the missed-check-in margin to 30 minutes" do
      expect(described_class.sentry_monitor_config.checkin_margin).to eq(30)
    end

    it "sets the monitor's crontab to the same schedule as config/recurring.yml's production entry" do
      recurring = YAML.load_file(Rails.root.join("config", "recurring.yml"))
      expected_schedule = recurring.fetch("production").fetch("replication_lag_check").fetch("schedule")

      expect(described_class.sentry_monitor_config.schedule.value).to eq(expected_schedule)
    end

    it "sends an in-progress check-in and then a successful check-in on a healthy run, both against the monitor slug" do
      stub_object_names(["litestream/test/ltx/0/0000000000000001-0000000000000005.ltx"])

      described_class.perform_now

      expect(Sentry).to have_received(:capture_check_in)
        .with(described_class.sentry_monitor_slug, :in_progress, hash_including(monitor_config: an_instance_of(Sentry::Cron::MonitorConfig)))
        .ordered
      expect(Sentry).to have_received(:capture_check_in)
        .with(described_class.sentry_monitor_slug, :ok, hash_including(monitor_config: an_instance_of(Sentry::Cron::MonitorConfig)))
        .ordered
    end

    it "raises out of perform_now and sends an error check-in when something unexpected happens inside the run" do
      error = StandardError.new("something broke")
      stub_reader_call_raising(error)

      expect { described_class.perform_now }.to raise_error(error)

      expect(Sentry).to have_received(:capture_check_in)
        .with(described_class.sentry_monitor_slug, :error, hash_including(monitor_config: an_instance_of(Sentry::Cron::MonitorConfig)))
    end
  end

  describe "ReplicationHeartbeat.singleton" do
    it "returns the row at primary key 1, and the same row on a second call" do
      first = ReplicationHeartbeat.singleton
      second = ReplicationHeartbeat.singleton

      expect(first.id).to eq(ReplicationHeartbeat::SINGLETON_ID)
      expect(second.id).to eq(first.id)
      expect(ReplicationHeartbeat.count).to eq(1)
    end
  end
end
