# frozen_string_literal: true

class CreateBillSummaryReports < ActiveRecord::Migration[8.1]
  def change
    create_table :bill_summary_reports do |t|
      t.references :bill, null: false, foreign_key: {on_delete: :cascade}
      t.references :user, foreign_key: {to_table: :users, on_delete: :nullify}
      t.string :reason, null: false
      t.text :details
      t.integer :status, default: 0, null: false
      t.text :summary_snapshot
      t.boolean :summary_ai_unreviewed, default: true, null: false
      t.string :ip_address
      t.string :user_agent
      t.references :resolved_by, foreign_key: {to_table: :users, on_delete: :nullify}
      t.datetime :resolved_at
      t.text :admin_notes

      t.timestamps
    end

    add_index :bill_summary_reports, :status
    add_index :bill_summary_reports, %i[bill_id status]
    add_index :bill_summary_reports, %i[bill_id created_at]
    add_index :bill_summary_reports, %i[ip_address created_at]
  end
end
