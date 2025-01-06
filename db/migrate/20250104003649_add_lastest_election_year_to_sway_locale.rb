class AddLastestElectionYearToSwayLocale < ActiveRecord::Migration[7.2]
  def change
    add_column :sway_locales, :latest_election_year, :integer, null: false, default: 2024
  end
end
