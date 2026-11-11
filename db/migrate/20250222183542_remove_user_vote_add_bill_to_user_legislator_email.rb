class RemoveUserVoteAddBillToUserLegislatorEmail < ActiveRecord::Migration[8.0]
  def change
    add_reference :user_legislator_emails, :bill, foreign_key: true

    remove_column :user_legislator_emails, :user_vote_id, :integer
  end
end
