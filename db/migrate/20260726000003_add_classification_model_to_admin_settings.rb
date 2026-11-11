# frozen_string_literal: true

# @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Choosing the model for one regeneration#Classification has its own model column]]
# @lat: [[admin-setting-model-list#Why the creating migration hardcodes the seed value]]
class AddClassificationModelToAdminSettings < ActiveRecord::Migration[8.1]
  def change
    add_column :admin_settings, :classification_model, :string,
      null: false,
      default: "claude-haiku-5-5"
  end
end
