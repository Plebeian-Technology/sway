# frozen_string_literal: true

# @lat: [[query-plan-indexes#Single-column indexes a composite already covers]]
class AddBillLookupIndexToLegislatorVotes < ActiveRecord::Migration[8.1]
  def up
    add_index :legislator_votes, :bill_id
  end

  def down
    remove_index :legislator_votes, :bill_id
  end
end
