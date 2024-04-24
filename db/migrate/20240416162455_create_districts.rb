# typed: true
class CreateDistricts < ActiveRecord::Migration[7.1]
  def change
    create_table :districts do |t|
      t.string :name

      t.references :sway_locale, null: false, foreign_key: true

      t.timestamps
    end
  end
end
