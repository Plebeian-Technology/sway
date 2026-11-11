# frozen_string_literal: true

# The day a term really ended, when a source publishes it.
# ended_on_source distinguishes "published" (the jurisdiction's own record)
# from "observed".
#
# @lat: [[retire-departed-members-safety-design#Why a stored term widens to hold a real end date, instead of narrowing#Why TermWindow.ends_on defaults to the successor's convening date]]
class AddEndedOnToLegislatorTerms < ActiveRecord::Migration[8.1]
  def change
    add_column :legislator_terms, :ended_on, :date, null: true
    add_column :legislator_terms, :ended_on_source, :string, null: true
  end
end
