# frozen_string_literal: true

class CreateActiveStorageVariantRecordsIfMissing < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:active_storage_variant_records)

    # rubocop:disable Rails/CreateTableWithTimestamps
    create_table :active_storage_variant_records, id: :primary_key do |t|
      t.belongs_to :blob, null: false, index: false, type: :bigint
      t.string :variation_digest, null: false

      t.index %i[blob_id variation_digest], name: :index_active_storage_variant_records_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end
    # rubocop:enable Rails/CreateTableWithTimestamps
  end
end
