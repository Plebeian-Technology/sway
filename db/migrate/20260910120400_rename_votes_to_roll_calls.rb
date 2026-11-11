# frozen_string_literal: true

class RenameVotesToRollCalls < ActiveRecord::Migration[8.1]
  def change
    rename_table :votes, :roll_calls
  end
end
