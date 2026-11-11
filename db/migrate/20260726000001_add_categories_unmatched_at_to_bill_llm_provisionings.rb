# frozen_string_literal: true

# @lat: [[bills-category-filter#Bills category filter#Why a bill matches on ANY category]]
class AddCategoriesUnmatchedAtToBillLlmProvisionings < ActiveRecord::Migration[8.1]
  def change
    add_column :bill_llm_provisionings, :categories_unmatched_at, :datetime

    # Partial index over the STAMPED rows only, which is the opposite of what
    # this note used to claim. It cannot serve the backfill, whose filter keeps
    # rows where the stamp IS NULL or is older than the summary it judged —
    # no index with this predicate can answer either half. What it does serve
    # is the admin re-arm, which asks for exactly the stamped rows
    # (Admin::CategoriesController#rearm_unmatched_categorization!).
    add_index :bill_llm_provisionings,
      :categories_unmatched_at,
      where: "categories_unmatched_at IS NOT NULL",
      name: "index_bill_llm_provisionings_on_categories_unmatched_at"
  end
end
