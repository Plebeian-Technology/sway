# frozen_string_literal: true

class CreateRegistrationFunnelEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :registration_funnel_events do |t|
      t.string :visitor_token, null: false, limit: 64
      t.references :user, null: true, foreign_key: {on_delete: :nullify}
      t.integer :step, null: false
      t.string :attribution_key, null: true, limit: 100
      t.json :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :registration_funnel_events, %i[step created_at],
      name: "index_registration_funnel_events_on_step_and_created_at"
    add_index :registration_funnel_events, :visitor_token,
      name: "index_registration_funnel_events_on_visitor_token"
    add_index :registration_funnel_events, %i[attribution_key created_at],
      name: "index_registration_funnel_events_on_attribution_and_created_at"
  end
end
