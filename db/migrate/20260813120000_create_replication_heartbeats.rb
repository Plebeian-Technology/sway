# frozen_string_literal: true

# @lat: [[replication-lag-check]]
class CreateReplicationHeartbeats < ActiveRecord::Migration[8.1]
  # Bare stand-in class, not the real ReplicationHeartbeat model.
  #
  # @lat: [[migrate-from-empty-spec-design#The failure pattern]]
  class MigrationReplicationHeartbeat < ActiveRecord::Base
    self.table_name = "replication_heartbeats"
  end

  def change
    create_table :replication_heartbeats do |t|
      t.datetime :checked_at, null: false
      # Absent (nil) means no run has ever read a number yet — the very first
      # scheduled check, before it has recorded anything (D-09).
      t.integer :last_replica_txid
      t.integer :consecutive_stalls, null: false, default: 0
      t.integer :consecutive_read_failures, null: false, default: 0
      t.integer :consecutive_empty_listings, null: false, default: 0
      # Set the moment the FIRST stall in a run of stalls is seen; nil while
      # healthy. Plan 02 reads this to report how long the current stall has
      # lasted.
      t.datetime :stalled_since
      t.timestamps

      # D-17: the table holds exactly one row, at id 1. Nothing else in this
      # repo has used a check constraint before this — if a future run of this
      # migration shows SQLite silently drops it from db/schema.rb, remove it
      # and rely on ReplicationHeartbeat's `validate :enforce_single_row`
      # instead (app/models/replication_heartbeat.rb).
      t.check_constraint "id = 1", name: "replication_heartbeats_single_row"
    end

    reversible do |dir|
      dir.up do
        # Load-bearing: MigrationReplicationHeartbeat was defined before the
        # table existed.
        MigrationReplicationHeartbeat.reset_column_information
        # Scoped by id: 1 rather than by find_or_create_by!(checked_at: ...),
        # which would search on checked_at and insert a second row on every
        # migration re-run whose current time differs from the first. Safe to
        # run twice — production runs seeds on every boot by design.
        MigrationReplicationHeartbeat.where(id: 1).first_or_create!(checked_at: Time.current)
      end
    end
  end
end
