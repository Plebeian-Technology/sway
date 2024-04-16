class CreateBills < ActiveRecord::Migration[7.1]
  def change
    create_table :bills do |t|
      t.string :external_id, null: false
      t.string :external_version
      t.string :title, null: false
      t.string :link
      t.string :chamber, null: false
      t.datetime :introduced_date_time_utc, null: false
      t.datetime :house_vote_date_time_utc
      t.datetime :senate_vote_date_time_utc
      t.string :level, null: false
      t.string :category, null: false
      
      t.references :sponsor, null: false, foreign_key: { to_table: :legislators }
      t.references :sway_locale, null: false, foreign_key: true

      t.timestamps
    end
  end
end
