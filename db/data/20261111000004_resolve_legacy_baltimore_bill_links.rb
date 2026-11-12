# frozen_string_literal: true

# @lat: [[legistar-detail-url-resolution#Backfill procedure for stored Baltimore bills]]
class ResolveLegacyBaltimoreBillLinks < ActiveRecord::Migration[8.1]
  def up
    BaltimoreBillLinkBackfillService.call(raise_on_failure: true)
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
