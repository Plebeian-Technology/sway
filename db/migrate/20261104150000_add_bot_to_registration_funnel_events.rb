# frozen_string_literal: true

# @lat: [[registration-funnel-telemetry#Bot traffic classification]]
class AddBotToRegistrationFunnelEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :registration_funnel_events, :bot, :boolean, null: false, default: false
    add_index :registration_funnel_events, [:bot, :created_at, :step],
      name: "index_registration_funnel_events_on_bot_created_at_step"
  end
end
