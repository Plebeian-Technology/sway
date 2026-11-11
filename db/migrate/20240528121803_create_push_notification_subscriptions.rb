class CreatePushNotificationSubscriptions < ActiveRecord::Migration[7.1]
  def change
    create_table :push_notification_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :endpoint
      t.string :p256dh
      t.string :auth
      t.boolean :subscribed, null: false, default: false

      t.timestamps
    end
  end
end
