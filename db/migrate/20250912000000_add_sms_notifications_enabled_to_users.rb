class AddSmsNotificationsEnabledToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :sms_notifications_enabled, :boolean, default: false
  end
end
