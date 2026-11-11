# frozen_string_literal: true

# @lat: [[admin-setting-model-list#Dynamic offered models and OpenRouter catalog]]
class AddReasoningEffortsToAdminSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_settings, :summarization_reasoning_effort, :string, default: nil
    add_column :admin_settings, :classification_reasoning_effort, :string, default: nil
  end
end
