# frozen_string_literal: true

# @lat: [[migrate-from-empty-spec-design#Comparing a migrated table with db/schema.rb]]
class DropLegislatorTermIdFromLegislatorVotes < ActiveRecord::Migration[8.1]
  TERM_INDEXES = %w[
    index_legislator_votes_on_bill_and_person_null_term_unique
    index_legislator_votes_on_bill_and_term_unique
    index_legislator_votes_on_legislator_term_id
  ].freeze

  def up
    if column_exists?(:legislator_votes, :legislator_term_id)
      if foreign_key_exists?(:legislator_votes, :legislator_terms)
        remove_foreign_key :legislator_votes, :legislator_terms
      end
      TERM_INDEXES.each do |name|
        remove_index :legislator_votes, name: name if index_name_exists?(:legislator_votes, name)
      end
      remove_column :legislator_votes, :legislator_term_id
    end

    unless index_name_exists?(:legislator_votes, "index_legislator_votes_on_bill_id_and_legislator_id")
      add_index :legislator_votes, [:bill_id, :legislator_id], unique: true
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
