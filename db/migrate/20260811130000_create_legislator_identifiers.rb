# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#Roster identity during seeding#Identity is a table of rows, not one column]]
class CreateLegislatorIdentifiers < ActiveRecord::Migration[8.1]
  def change
    create_table :legislator_identifiers do |t|
      t.references :legislator, null: false, foreign_key: true, index: true
      t.references :sway_locale, null: false, foreign_key: true, index: false

      # Which source calls the person this. See LegislatorIdentity for the
      # names in use and what each one carries.
      t.string :source, null: false

      # What that source calls them.
      t.string :value, null: false

      t.timestamps
    end

    add_index :legislator_identifiers,
      %i[sway_locale_id source value],
      unique: true,
      name: "index_legislator_identifiers_on_locale_and_source_and_value"
  end
end
