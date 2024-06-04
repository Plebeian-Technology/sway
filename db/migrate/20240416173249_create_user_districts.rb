# typed: true
class CreateUserDistricts < ActiveRecord::Migration[7.1]
  def change
    create_table :user_districts do |t|
      t.references :district, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
