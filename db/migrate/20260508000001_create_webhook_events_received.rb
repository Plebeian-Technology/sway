# frozen_string_literal: true

# Phase 48 D-07: dedup table for at-least-once webhook delivery.
# Every Webhooks::Legislation receiver action begins with a DB-level
# uniqueness check on event_id (UUID4 generated once on FastAPI side per
# Phase 48 D-05). Race-safe: INSERT-and-rescue ActiveRecord::RecordNotUnique
# (RESEARCH Pitfall 2). PRIMARY KEY enforces uniqueness atomically.
class CreateWebhookEventsReceived < ActiveRecord::Migration[8.1]
  def change
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
