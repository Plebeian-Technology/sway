class CreateUserLegislators < ActiveRecord::Migration[7.1]
  def change
    create_table :user_legislators do |t|
      t.references :legislator, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true

      t.timestamps
    end
  end
end
