# frozen_string_literal: true

# Phase 54 SPEC R6 — singleton-shaped admin_settings table backing the
# Claude summarization-model selection.
#
# @lat: [[admin-setting-model-list#Why the seed uses first_or_create!, not find_or_create_by!]]
class CreateAdminSettings < ActiveRecord::Migration[8.1]
  # @lat: [[migrate-from-empty-spec-design#The failure pattern]]
  class MigrationAdminSetting < ActiveRecord::Base
    self.table_name = "admin_settings"
  end

  def change
    create_table :admin_settings do |t|
      # NOT NULL — validation in the model enforces inclusion in the
      # SUPPORTED_MODELS allowlist; we also want the DB to reject a manual
      # INSERT lacking the value.
      t.string :summarization_model, null: false

      # Nullable + FK -> users — records WHO last changed the setting (Plan 02
      # admin UI will populate this on update). nil is allowed because the
      # seed row has no user attribution.
      t.references :updated_by,
        foreign_key: {to_table: :users},
        null: true,
        index: true

      t.timestamps
    end

    reversible do |dir|
      dir.up do
        # first_or_create!, not find_or_create_by!.
        # @lat: [[admin-setting-model-list#Why the seed uses first_or_create!, not find_or_create_by!]]
        MigrationAdminSetting.reset_column_information
        MigrationAdminSetting.first_or_create!(summarization_model: "claude-haiku-5-5")
      end
    end
  end
end
