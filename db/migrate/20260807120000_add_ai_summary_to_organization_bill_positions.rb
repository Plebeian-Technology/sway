# frozen_string_literal: true

# Holds the model's own words for an organization position, so the bill page
# can tell a reader that a machine wrote this text and nobody revised it.
# NULL means no machine wrote this text (an admin typed the position in).
#
# @lat: [[bill-summary-ai-unreviewed-detection#Why an organization position needed its own column instead]]
class AddAiSummaryToOrganizationBillPositions < ActiveRecord::Migration[8.1]
  def change
    add_column :organization_bill_positions, :ai_summary, :text
  end
end
