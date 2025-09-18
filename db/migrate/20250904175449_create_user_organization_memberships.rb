class CreateUserOrganizationMemberships < ActiveRecord::Migration[8.0]
    def change
        create_table :user_organization_memberships do |t|
            t.references :user, null: false, foreign_key: true
            t.references :organization, null: false, foreign_key: true
            t.integer :role, null: false, default: :standard # 0: standard, 1: admin

            t.timestamps
        end

        add_index :user_organization_memberships, %i[user_id organization_id], unique: true
    end
end
