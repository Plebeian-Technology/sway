# frozen_string_literal: true

# @lat: [[sway-google-cloud-storage#Sway Google Cloud Storage#A stored file name is not an address]]
class ClearOurOwnAddressFromOrganizationIcons < ActiveRecord::Migration[8.1]
  # @lat: [[migrations-name-no-model#Stand-in classes]]
  class MigrationOrganization < ActiveRecord::Base
    self.table_name = "organizations"
  end

  OUR_OWN_STORAGE = "%/rails/active_storage/%"

  def up
    # update_all on purpose: the save hook would enqueue mirroring for an
    # address we are removing.
    cleared = MigrationOrganization.where("icon_url LIKE ?", OUR_OWN_STORAGE).update_all(icon_url: nil)
    say "cleared our own address from #{cleared} organization icon_url values"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
