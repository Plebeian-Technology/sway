# frozen_string_literal: true

# @lat: [[migrations-name-no-model#Migrations name no model#A column nothing writes is dropped in its own change]]
class MakeUserLegislatorEmailsBillIdNotNull < ActiveRecord::Migration[8.1]
  def up
    null_count = connection.select_value(
      "SELECT COUNT(*) FROM user_legislator_emails WHERE bill_id IS NULL"
    ).to_i

    if null_count.positive?
      raise ActiveRecord::MigrationError,
        "#{null_count} user_legislator_emails row(s) have a null bill_id. " \
        "UserLegislatorEmail belongs_to :bill (required) and delegates sway_locale " \
        "to it, so a null bill_id is invalid data. Backfill or remove those rows, " \
        "then re-run this migration."
    end

    change_column_null :user_legislator_emails, :bill_id, false
  end

  def down
    change_column_null :user_legislator_emails, :bill_id, true
  end
end
