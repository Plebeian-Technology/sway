# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "seeds", "seedable")

# @lat: [[sway-google-cloud-storage#Historical photo URLs are retired by exact identity]]
RSpec.describe "Production snapshot legislator photos", :production_snapshot, type: :model do
  include_context "production snapshot (migrated)"

  let(:seed_guard) { Class.new { include Seedable }.new }

  # @lat: [[sway-google-cloud-storage#Historical photo URLs are retired by exact identity]]
  it "never refuses to re-seed a legislator whose photo is missing" do
    expect(Legislator.count).to be > 100

    missing_photo = Legislator.find_each.reject { |legislator| legislator.photo.attached? }
    expect(missing_photo).not_to be_empty,
      "no legislator is missing a photo, which has never been true of this snapshot — " \
      "check that the copy under test is the production one"

    unrepairable =
      missing_photo
        .select { |legislator| seed_guard.seed_or_skip?(legislator) }
        .map { |legislator| "#{legislator.external_id} (#{legislator.full_name})" }

    expect(unrepairable).to be_empty,
      "these have no photo AND the seeder refuses to write a new address, so no deploy can " \
      "give them one:\n  #{unrepairable.join("\n  ")}"
  end

  it "does not expose the four retired fallbacks or change the three blank identities" do
    retired = [
      ["baltimore", "maryland", "united_states", "kristefer-burnett-2020", "https://www.baltimorecitycouncil.com/sites/default/files/kristerfer_burnett-121_147.png"],
      ["baltimore", "maryland", "united_states", "eric-costello-2020", "https://www.baltimorecitycouncil.com/sites/default/files/Costello%20Web%20Image.jpg"],
      ["baltimore", "maryland", "united_states", "robert-stokes-2020", "https://www.baltimorecitycouncil.com/sites/default/files/robert_stokes_jr-121_147.png"],
      ["congress", "congress", "united_states", "S001222", "https://raw.githubusercontent.com/unitedstates/images/gh-pages/congress/225x275/S001222.jpg"]
    ]

    retired.each do |city, region_name, country, external_id, legacy_url|
      locale = SwayLocale.find_by!(city:, region_name:, country:)
      legislator = Legislator.find_by!(sway_locale: locale, external_id:)
      expect(legislator.photo_url).to be_nil,
        "#{external_id} still has a retired fallback address: #{legacy_url}"
      expect(MirroredAssetUrl.for(legislator.photo, fallback: legislator.photo_url)).not_to eq(legacy_url)
    end

    congress = SwayLocale.find_by!(city: "congress", region_name: "congress", country: "united_states")
    blank_identities = %w[T000489 A000383 G000608].map do |external_id|
      Legislator.find_by!(sway_locale: congress, external_id:)
    end
    expect(blank_identities.map(&:photo_url)).to all(be_nil)
    %w[A000383 G000608].each do |external_id|
      legislator = Legislator.find_by!(sway_locale: congress, external_id:)
      expect(LegislatorTerm.current.where(legislator_id: legislator.id)).to exist,
        "#{external_id} must retain its current term despite having no photo address"
    end
  end
end
