# frozen_string_literal: true

class AddPendingRepresentativeLocaleIdsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :pending_representative_locale_ids, :json, default: [], null: false
  end
end
