# frozen_string_literal: true

# Builds solid_cable_messages on the CABLE database.
#
# The class name differs from CreateSolidCableMessages on purpose. `db:migrate` runs
# every database in one process, so two migration files sharing a class name
# would reopen one class and silently redefine `change`.
#
# @lat: [[auxiliary-databases#Why cable and cache are provisioned by a migrations path]]
class CreateCableDatabaseMessages < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cable_messages do |t|
      t.binary :channel, null: false, limit: 1024
      t.binary :payload, null: false, limit: 536_870_912
      t.datetime :created_at, null: false
      t.integer :channel_hash, null: false, limit: 8

      t.index :channel, name: "index_solid_cable_messages_on_channel"
      t.index :channel_hash, name: "index_solid_cable_messages_on_channel_hash"
      t.index :created_at, name: "index_solid_cable_messages_on_created_at"
    end
  end
end
