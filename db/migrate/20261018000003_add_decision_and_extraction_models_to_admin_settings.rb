# frozen_string_literal: true

# @lat: [[admin-setting-model-list#Dynamic offered models and OpenRouter catalog]]
class AddDecisionAndExtractionModelsToAdminSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_settings, :decision_model, :string, default: "ScaleDown Classify Latest", null: false
    add_column :admin_settings, :extraction_model, :string, default: "ScaleDown Extract Latest", null: false
  end
end
