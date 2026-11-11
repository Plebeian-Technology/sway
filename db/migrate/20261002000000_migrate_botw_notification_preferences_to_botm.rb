# frozen_string_literal: true

class MigrateBotwNotificationPreferencesToBotm < ActiveRecord::Migration[8.1]
  def up
    execute <<-SQL
      UPDATE notification_preferences
      SET enabled = 0
      WHERE key = 'botm_announcement'
        AND user_id IN (
          SELECT user_id
          FROM notification_preferences
          WHERE key = 'botw_announcement' AND enabled = 0
        )
    SQL

    execute <<-SQL
      DELETE FROM notification_preferences
      WHERE key = 'botw_announcement'
        AND user_id IN (
          SELECT user_id
          FROM notification_preferences
          WHERE key = 'botm_announcement'
        )
    SQL

    execute <<-SQL
      UPDATE notification_preferences
      SET key = 'botm_announcement'
      WHERE key = 'botw_announcement'
    SQL
  end

  def down
    execute <<-SQL
      UPDATE notification_preferences
      SET enabled = 0
      WHERE key = 'botw_announcement'
        AND user_id IN (
          SELECT user_id
          FROM notification_preferences
          WHERE key = 'botm_announcement' AND enabled = 0
        )
    SQL

    execute <<-SQL
      DELETE FROM notification_preferences
      WHERE key = 'botm_announcement'
        AND user_id IN (
          SELECT user_id
          FROM notification_preferences
          WHERE key = 'botw_announcement'
        )
    SQL

    execute <<-SQL
      UPDATE notification_preferences
      SET key = 'botw_announcement'
      WHERE key = 'botm_announcement'
    SQL
  end
end
