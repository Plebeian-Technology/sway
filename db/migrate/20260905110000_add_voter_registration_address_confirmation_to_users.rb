# frozen_string_literal: true

class AddVoterRegistrationAddressConfirmationToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :is_voter_registration_address_confirmed, :boolean, null: false, default: false
  end
end
