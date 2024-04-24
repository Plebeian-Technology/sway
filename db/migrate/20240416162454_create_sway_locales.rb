# typed: true
class CreateSwayLocales < ActiveRecord::Migration[7.1]
  def change
    create_table :sway_locales do |t|
      t.string :city
      t.string :state
      t.string :country

      t.timestamps
    end
  end
end
