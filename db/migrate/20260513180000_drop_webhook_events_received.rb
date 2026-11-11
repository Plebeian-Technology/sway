# frozen_string_literal: true

# Phase 52 Plan 11 Task 4 — SPEC R11.
#
# Drops the dedup table that tracked at-least-once webhook deliveries from
# the FastAPI legislation service. Phase 52 collapses FastAPI into native
# Rails services; no inbound webhooks remain.
#
# The `down` block reverse-engineers the original
# 20260508000001_create_webhook_events_received.rb migration verbatim so
# rollback is unambiguous.
class DropWebhookEventsReceived < ActiveRecord::Migration[8.1]
  def up
    drop_table :webhook_events_received
  end

  def down
    create_table :webhook_events_received, id: false do |t|
      t.string    :event_id,      primary_key: true, null: false
      t.string    :event_name,    null: false
      t.string    :remote_run_id, null: false
      t.timestamp :received_at,   null: false
    end
    add_index :webhook_events_received, :remote_run_id
    add_index :webhook_events_received, :event_name
  end
end
