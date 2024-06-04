# typed: true

class CreateSwayLocales < ActiveRecord::Migration[7.1]
  def change
    create_table :sway_locales do |t|
      t.string :city, null: false
      t.string :state, null: false
      t.string :country, null: false, default: 'United States'

      t.timestamps
    end
  end
end
