class CreateUserOrganizationMembershipInvites < ActiveRecord::Migration[8.0]
    def change
        create_table :user_organization_membership_invites do |t|
            t.references :inviter, null: false, foreign_key: { to_table: :users }
            t.references :organization, null: false, foreign_key: true
            t.string :invitee_email, null: false

            t.timestamps
        end
    end
end
