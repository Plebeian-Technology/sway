class AddUniqueIndexToUserVotesByUserAndBill < ActiveRecord::Migration[8.0]
  class MigrationUserVote < ActiveRecord::Base
    self.table_name = "user_votes"
  end

  def up
    deduplicate_user_votes!
    add_index :user_votes, [:user_id, :bill_id], unique: true, name: "index_user_votes_on_user_id_and_bill_id"
  end

  def down
    remove_index :user_votes, name: "index_user_votes_on_user_id_and_bill_id"
  end

  private

  def deduplicate_user_votes!
    say_with_time("Removing duplicate user_votes per user and bill") do
      duplicate_pairs.each do |user_id, bill_id|
        keep_id =
          MigrationUserVote
            .where(user_id: user_id, bill_id: bill_id)
            .order(updated_at: :desc, created_at: :desc, id: :desc)
            .limit(1)
            .pick(:id)

        MigrationUserVote
          .where(user_id: user_id, bill_id: bill_id)
          .where.not(id: keep_id)
          .delete_all
      end
    end
  end

  def duplicate_pairs
    MigrationUserVote
      .group(:user_id, :bill_id)
      .having("COUNT(*) > 1")
      .pluck(:user_id, :bill_id)
  end
end
