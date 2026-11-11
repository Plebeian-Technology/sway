class AddStatusToUserLegislatorEmail < ActiveRecord::Migration[8.0]
  def change
    add_column :user_legislator_emails, :status, :integer, default: :pending, null: false
  end
end
