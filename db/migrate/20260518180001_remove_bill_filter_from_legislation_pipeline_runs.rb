# frozen_string_literal: true

# Drop the redundant legislation_pipeline_runs.bill_filter
# column. The canonical scoping field is now bill_id (FK). The prior
# data backfill migration (20260518180000) ensured every row's bill_id
# matches the historical bill_filter where the lookup resolved.
class RemoveBillFilterFromLegislationPipelineRuns < ActiveRecord::Migration[8.1]
  def up
    remove_column :legislation_pipeline_runs, :bill_filter
  end

  def down
    add_column :legislation_pipeline_runs, :bill_filter, :string

    # Best-effort re-derive from bill_id so a rollback leaves the column
    # populated for any existing rows. Unresolvable bill_ids stay nil
    # (the original bill_filter value is lost — same data as before
    # 20260518180000 ran).
    say_with_time "Re-deriving bill_filter from bill_id on rollback" do
      filled = 0
      ActiveRecord::Base.connection.exec_query(
        "SELECT id, bill_id FROM legislation_pipeline_runs WHERE bill_id IS NOT NULL",
      ).each do |row|
        external_id = ActiveRecord::Base.connection.exec_query(
          "SELECT external_id FROM bills WHERE id = ? LIMIT 1",
          "bill external_id lookup",
          [row["bill_id"]],
        ).first&.dig("external_id")
        next unless external_id

        ActiveRecord::Base.connection.exec_update(
          "UPDATE legislation_pipeline_runs SET bill_filter = ? WHERE id = ?",
          "re-derive bill_filter",
          [external_id, row["id"]],
        )
        filled += 1
      end
      filled
    end
  end
end
