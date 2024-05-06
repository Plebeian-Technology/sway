# typed: true

class CreateAddresses < ActiveRecord::Migration[7.1]
  def change
    create_table :addresses do |t|
      t.string :street, null: false
      t.string :street2
      t.string :street3
      t.string :city, null: false
      t.string :region_code, null: false
      t.string :postal_code, null: false
      t.string :country, null: false, default: 'US'
      t.float :latitude
      t.float :longitude

      t.timestamps
    end
  end
end
