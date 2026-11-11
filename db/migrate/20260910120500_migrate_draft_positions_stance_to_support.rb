# frozen_string_literal: true

class MigrateDraftPositionsStanceToSupport < ActiveRecord::Migration[8.1]
  class MigrationBillLlmProvisioning < ActiveRecord::Base
    self.table_name = "bill_llm_provisionings"
  end

  def up
    MigrationBillLlmProvisioning.where.not(draft_org_positions: nil).find_each do |provisioning|
      raw = provisioning.draft_org_positions
      positions = raw.is_a?(String) ? (JSON.parse(raw) rescue nil) : raw
      next unless positions.is_a?(Array)

      changed = false
      positions.each do |pos|
        if pos.is_a?(Hash) && pos.key?("stance") && !pos.key?("support")
          pos["support"] = pos["stance"]
          changed = true
        end
      end

      provisioning.update_column(:draft_org_positions, JSON.generate(positions)) if changed
    end
  end

  def down
    # No-op: both support and stance are preserved
  end
end

