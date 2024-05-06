# typed: true
class CreateLegislators < ActiveRecord::Migration[7.1]
  def change
    create_table :legislators do |t|
      t.string :external_id, null: false
      t.boolean :active, null: false
      t.string :link
      t.string :email
      t.string :title
      t.string :first_name, null: false
      t.string :last_name, null: false
      t.string :phone
      t.string :fax
      t.string :party, null: false
      t.string :photo_url

      t.references :address, null: false, foreign_key: true
      t.references :district, null: false, foreign_key: true

      t.timestamps
    end
  end
end
