# frozen_string_literal: true

# @lat: [[sway-google-cloud-storage#Historical photo URLs are retired by exact identity]]
class RetireUnavailableLegislatorPhotoUrls < ActiveRecord::Migration[8.1]
  class MigrationSwayLocale < ActiveRecord::Base
    self.table_name = "sway_locales"
  end

  class MigrationLegislator < ActiveRecord::Base
    self.table_name = "legislators"
  end

  RETIREMENTS = [
    {
      city: "baltimore",
      region_name: "maryland",
      country: "united_states",
      external_id: "kristefer-burnett-2020",
      photo_url: "https://www.baltimorecitycouncil.com/sites/default/files/kristerfer_burnett-121_147.png"
    },
    {
      city: "baltimore",
      region_name: "maryland",
      country: "united_states",
      external_id: "eric-costello-2020",
      photo_url: "https://www.baltimorecitycouncil.com/sites/default/files/Costello%20Web%20Image.jpg"
    },
    {
      city: "baltimore",
      region_name: "maryland",
      country: "united_states",
      external_id: "robert-stokes-2020",
      photo_url: "https://www.baltimorecitycouncil.com/sites/default/files/robert_stokes_jr-121_147.png"
    },
    {
      city: "congress",
      region_name: "congress",
      country: "united_states",
      external_id: "S001222",
      photo_url: "https://raw.githubusercontent.com/unitedstates/images/gh-pages/congress/225x275/S001222.jpg"
    }
  ].freeze

  def up
    cleared = RETIREMENTS.sum do |retirement|
      locale_id = MigrationSwayLocale.where(
        city: retirement.fetch(:city),
        region_name: retirement.fetch(:region_name),
        country: retirement.fetch(:country)
      ).pick(:id)
      next 0 unless locale_id

      MigrationLegislator.where(
        sway_locale_id: locale_id,
        external_id: retirement.fetch(:external_id),
        photo_url: retirement.fetch(:photo_url)
      ).update_all(photo_url: nil)
    end

    say "retired #{cleared} exact unavailable legislator photo fallbacks"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
