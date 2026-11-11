# frozen_string_literal: true

# @lat: [[bill-of-the-month-notify-job-per-locale-fix#Web push vs native push fan-out]]
class RenameBotwAnnouncementPreferencesToBotm < ActiveRecord::Migration[8.1]
  def up
    execute <<~SQL.squish
      DELETE FROM notification_preferences
      WHERE key = 'botw_announcement'
        AND user_id IN (
          SELECT user_id
          FROM notification_preferences
          WHERE key = 'botm_announcement'
        )
    SQL

    execute <<~SQL.squish
      UPDATE notification_preferences
      SET key = 'botm_announcement'
      WHERE key = 'botw_announcement'
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
