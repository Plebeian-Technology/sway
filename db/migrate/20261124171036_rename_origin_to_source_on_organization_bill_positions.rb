# frozen_string_literal: true

# @lat: [[news-org-position-persistence#Position origin and affiliation]]
class RenameOriginToSourceOnOrganizationBillPositions < ActiveRecord::Migration[8.1]
  # Seconds between an approved change and the position write it caused.
  APPROVAL_WRITE_TOLERANCE_SECONDS = 5

  # OrganizationBillPositionChange status value for approved.
  APPROVED_STATUS = 1

  def up
    rename_column :organization_bill_positions, :origin, :source_kind
    rename_column :organization_bill_positions, :origin_url, :source_url
    backfill_organization_source_kind
  end

  def down
    rename_column :organization_bill_positions, :source_url, :origin_url
    rename_column :organization_bill_positions, :source_kind, :origin
  end

  # @lat: [[news-org-position-persistence#Position origin and affiliation#Existing positions]]
  def backfill_organization_source_kind
    execute <<~SQL.squish
      UPDATE organization_bill_positions
      SET source_kind = 'organization'
      WHERE EXISTS (
        SELECT 1 FROM organization_bill_position_changes changes
        WHERE changes.organization_bill_position_id = organization_bill_positions.id
          AND changes.status = #{APPROVED_STATUS}
          AND julianday(changes.updated_at) >=
            julianday(organization_bill_positions.updated_at) - #{APPROVAL_WRITE_TOLERANCE_SECONDS} / 86400.0
      )
    SQL
  end
end
