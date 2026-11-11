class CreateUserLegislatorEmails < ActiveRecord::Migration[8.0]
  def change
    create_table :user_legislator_emails do |t|
      t.belongs_to :user_legislator, null: false, foreign_key: true
      t.belongs_to :user_vote, null: false, foreign_key: true
      t.string :message

      t.timestamps
    end
  end
end
