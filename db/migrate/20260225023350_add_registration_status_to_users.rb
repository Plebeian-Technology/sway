class AddRegistrationStatusToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :registration_status, :string, default: "pending"
  end
end
