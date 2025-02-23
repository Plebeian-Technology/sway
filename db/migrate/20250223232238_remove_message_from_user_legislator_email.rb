class RemoveMessageFromUserLegislatorEmail < ActiveRecord::Migration[8.0]
  def change
    remove_column :user_legislator_emails, :message, :string
  end
end
