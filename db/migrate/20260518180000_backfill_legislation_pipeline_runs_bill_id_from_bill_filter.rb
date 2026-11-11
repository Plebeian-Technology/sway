# frozen_string_literal: true

# @lat: [[migrations-name-no-model#Migrations name no model#A column nothing writes is dropped in its own change]]
class BackfillLegislationPipelineRunsBillIdFromBillFilter < ActiveRecord::Migration[8.1]
  def up
    candidates = ActiveRecord::Base.connection.exec_query(<<~SQL).to_a
      SELECT id, bill_filter
      FROM legislation_pipeline_runs
      WHERE bill_id IS NULL
        AND bill_filter IS NOT NULL
        AND TRIM(bill_filter) != ''
    SQL

    say_with_time "Backfilling bill_id from bill_filter for #{candidates.size} runs" do
      filled = 0
      unresolved = []

      candidates.each do |row|
        external_id = row["bill_filter"].to_s.strip
        bill_id = ActiveRecord::Base.connection.exec_query(
          "SELECT id FROM bills WHERE external_id = ? LIMIT 1",
          "bill lookup",
          [external_id],
        ).first&.dig("id")

        if bill_id
          ActiveRecord::Base.connection.exec_update(
            "UPDATE legislation_pipeline_runs SET bill_id = ? WHERE id = ?",
            "backfill bill_id",
            [bill_id, row["id"]],
          )
          filled += 1
        else
          unresolved << { run_id: row["id"], bill_filter: external_id }
        end
      end

      say "Filled bill_id on #{filled} runs"
      say "Unresolved (bill_filter did not match any Bill#external_id): #{unresolved.size}", true
      unresolved.each { |row| say "  run ##{row[:run_id]}: bill_filter=#{row[:bill_filter].inspect}", true }
      filled
    end
  end

  def down
    # No-op: we only ever fill bill_id, never clear it. Clearing here would
    # break the post-drop code path (which has no bill_filter column to
    # fall back to) and the original bill_filter data is preserved on the
    # row until the column-drop migration runs.
  end
end
