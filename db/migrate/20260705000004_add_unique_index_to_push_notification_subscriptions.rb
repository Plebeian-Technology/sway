# frozen_string_literal: true

# WS3.22.7: the create path did an in-Ruby existence check then create!, with only
# a non-unique user_id index — so two concurrent enable clicks both missed the
# check and inserted duplicate (user_id, endpoint) rows, producing duplicate web
# pushes. Add a unique (user_id, endpoint) index so the DB is the source of truth;
# the controller now rescues RecordNotUnique and resolves to the winning row.
class AddUniqueIndexToPushNotificationSubscriptions < ActiveRecord::Migration[8.1]
  def up
    # Collapse any pre-existing duplicates first — keep the newest (MAX id) row
    # per (user_id, endpoint) — or the unique index cannot be created. NULL
    # endpoints are left untouched (SQLite treats NULLs as distinct, and a real
    # subscription always carries an endpoint).
    execute(<<~SQL.squish)
      DELETE FROM push_notification_subscriptions
      WHERE endpoint IS NOT NULL
        AND id NOT IN (
          SELECT MAX(id) FROM push_notification_subscriptions
          WHERE endpoint IS NOT NULL
          GROUP BY user_id, endpoint
        )
    SQL

    add_index :push_notification_subscriptions, %i[user_id endpoint], unique: true
  end

  def down
    remove_index :push_notification_subscriptions, %i[user_id endpoint]
  end
end
