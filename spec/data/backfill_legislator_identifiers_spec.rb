# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260811140000_backfill_legislator_identifiers")

RSpec.describe "BackfillLegislatorIdentifiers data migration", type: :model do
  let(:baltimore) do
    create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
  end

  it "records a Baltimore row whose external_id is already the composite seat-and-name form" do
    legislator = create(:legislator, sway_locale: baltimore,
      external_id: "baltimore-district-1|mark-parker", first_name: "Mark", last_name: "Parker")

    expect { BackfillLegislatorIdentifiers.new.up }.not_to raise_error

    identifier = LegislatorIdentifier.find_by(legislator:, sway_locale: baltimore)
    expect(identifier).to have_attributes(
      source: LegislatorIdentity::SEAT_AND_NAME,
      value: "baltimore-district-1|mark-parker"
    )
    expect(legislator.reload.external_id).to eq("baltimore-district-1|mark-parker")
  end

  it "does not duplicate the identifier a row already holds" do
    legislator = create(:legislator, sway_locale: baltimore,
      external_id: "baltimore-district-1|mark-parker", first_name: "Mark", last_name: "Parker")
    identity = LegislatorIdentity.new(
      source: LegislatorIdentity::SEAT_AND_NAME, value: "baltimore-district-1|mark-parker"
    )
    existing = LegislatorIdentifier.record!(legislator:, identity:)

    expect { BackfillLegislatorIdentifiers.new.up }.not_to raise_error

    expect(LegislatorIdentifier.where(legislator:).count).to eq(1)
    expect(LegislatorIdentifier.find(existing.id)).to be_present
    expect(legislator.reload.external_id).to eq("baltimore-district-1|mark-parker")
  end

  it "records a plain seat-keyed row and moves its external_id to the composite form" do
    legislator = create(:legislator, sway_locale: baltimore,
      external_id: "baltimore-district-1", first_name: "Mark", last_name: "Parker")

    BackfillLegislatorIdentifiers.new.up

    identifier = LegislatorIdentifier.find_by(legislator:, sway_locale: baltimore)
    expect(identifier).to have_attributes(
      source: LegislatorIdentity::SEAT_AND_NAME,
      value: "baltimore-district-1|mark-parker"
    )
    expect(legislator.reload.external_id).to eq("baltimore-district-1|mark-parker")
  end

  it "reports a genuine collision and leaves both rows unchanged" do
    already_migrated = create(:legislator, sway_locale: baltimore,
      external_id: "baltimore-district-1|mark-parker", first_name: "Mark", last_name: "Parker")
    identity = LegislatorIdentity.new(
      source: LegislatorIdentity::SEAT_AND_NAME, value: "baltimore-district-1|mark-parker"
    )
    LegislatorIdentifier.record!(legislator: already_migrated, identity:)
    unmigrated = create(:legislator, sway_locale: baltimore,
      external_id: "baltimore-district-1", first_name: "Mark", last_name: "Parker")

    BackfillLegislatorIdentifiers.new.up

    expect(LegislatorIdentifier.where(legislator: unmigrated)).to be_empty
    expect(unmigrated.reload.external_id).to eq("baltimore-district-1")
    expect(already_migrated.reload.external_id).to eq("baltimore-district-1|mark-parker")
    expect(
      LegislatorIdentifier.where(sway_locale: baltimore, source: LegislatorIdentity::SEAT_AND_NAME,
        value: "baltimore-district-1|mark-parker").count
    ).to eq(1)
  end
end
