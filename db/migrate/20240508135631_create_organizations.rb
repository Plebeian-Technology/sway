class CreateOrganizations < ActiveRecord::Migration[7.1]
  def change
    create_table :organizations do |t|
      t.references :sway_locale, null: false, foreign_key: true
      t.string :name, null: false
      t.string :icon_path

      t.timestamps
    end

    add_index :organizations, [:name, :sway_locale_id], unique: true
  end
end
