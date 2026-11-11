# frozen_string_literal: true

# @lat: [[auxiliary-databases#Why cable and cache are provisioned by a migrations path]]
# Mirrors db/cache_schema.rb in the solid_cache gem.
class CreateCacheDatabaseEntries < ActiveRecord::Migration[8.1]
  def change
    create_table :solid_cache_entries do |t|
      t.binary :key, null: false, limit: 1024
      t.binary :value, null: false, limit: 536_870_912
      t.datetime :created_at, null: false
      t.integer :key_hash, null: false, limit: 8
      t.integer :byte_size, null: false, limit: 4

      t.index :byte_size, name: "index_solid_cache_entries_on_byte_size"
      t.index [:key_hash, :byte_size], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
      t.index :key_hash, name: "index_solid_cache_entries_on_key_hash", unique: true
    end
  end
end
