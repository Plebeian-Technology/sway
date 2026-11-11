# frozen_string_literal: true

require "rails_helper"

# == Schema Information
#
# Table name: seats
# Database name: primary
#
#  id              :integer          not null, primary key
#  chamber         :string           not null
#  seat_identifier :string           not null
#  title           :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  district_id     :integer          not null
#
# Indexes
#
#  index_seats_on_district_id                      (district_id)
#  index_seats_on_district_id_and_seat_identifier  (district_id,seat_identifier) UNIQUE
#
# Foreign Keys
#
#  district_id  (district_id => districts.id)
#
RSpec.describe Seat, type: :model do
  let(:sway_locale) { create(:sway_locale, :congress) }
  let(:district) { create(:district, sway_locale:, name: "MD0") }

  it "allows two explicit office identities in one district" do
    first = described_class.create!(
      district:,
      seat_identifier: "md-senate-class-1",
      title: "United States Senator",
      chamber: "Senate"
    )
    second = described_class.create!(
      district:,
      seat_identifier: "md-senate-class-3",
      title: "United States Senator",
      chamber: "Senate"
    )

    expect(district.seats).to contain_exactly(first, second)
  end

  it "rejects a seat from another district" do
    other_district = create(:district, sway_locale:, name: "MD1")
    seat = described_class.create!(
      district: other_district,
      seat_identifier: "md-house-district-1",
      title: "Delegate",
      chamber: "House"
    )
    term = build(:legislator_term, district:, seat:, legislator: create(:legislator, sway_locale:))

    expect(term).not_to be_valid
    expect(term.errors[:seat]).to be_present
  end

  it "does not overwrite metadata for an existing source office identity" do
    Seat.create!(
      district:,
      seat_identifier: "md-senate-class-1",
      title: "United States Senator",
      chamber: "Senate"
    )

    expect {
      described_class.find_or_create_by_identity!(
        district:,
        office_identity: "md-senate-class-1",
        title: "Different Title",
        chamber: "Senate"
      )
    }.to raise_error(Seat::IdentityConflictError)
  end

  it "rejects a resolved term with an empty service interval" do
    seat = described_class.create!(
      district:,
      seat_identifier: "md-senate-class-1",
      title: "United States Senator",
      chamber: "Senate"
    )
    term = build(
      :legislator_term,
      district:,
      seat:,
      legislator: create(:legislator, sway_locale:),
      began_on: TermWindow.convening_date(sway_locale, 2025),
      began_on_source: LegislatorTerm::DateSource::PUBLISHED,
      ended_on: TermWindow.convening_date(sway_locale, 2025),
      ended_on_source: LegislatorTerm::DateSource::PUBLISHED
    )

    expect(term).not_to be_valid
    expect(term.errors[:seat]).to be_present
  end

  it "does not allow a persisted resolved term to lose its seat" do
    seat = described_class.create!(
      district:,
      seat_identifier: "md-senate-class-1",
      title: "United States Senator",
      chamber: "Senate"
    )
    term = create(
      :legislator_term,
      district:,
      seat:,
      legislator: create(:legislator, sway_locale:)
    )

    term.seat = nil
    expect(term).not_to be_valid
    expect(term.errors[:seat]).to be_present
    expect { term.update_columns(seat_id: nil) }
      .to raise_error(Seats::UnresolvedSeatError)
    expect(term.reload.seat_id).to eq(seat.id)
  end

  it "does not allow save! to clear an existing seat association" do
    seat = described_class.create!(
      district:,
      seat_identifier: "md-senate-class-1",
      title: "United States Senator",
      chamber: "Senate"
    )
    term = create(
      :legislator_term,
      district:,
      seat:,
      legislator: create(:legislator, sway_locale:)
    )
    term.seat_id = nil

    expect(term.save).to be(false)
    expect(term.reload.seat_id).to eq(seat.id)
  end

  it "rejects a resolved term whose legislator belongs to another locale" do
    seat = described_class.create!(
      district:,
      seat_identifier: "md-senate-class-1",
      title: "United States Senator",
      chamber: "Senate"
    )
    other_locale = create(:sway_locale, city: "baltimore", state: "MD", country: "united_states")
    term = build(
      :legislator_term,
      district:,
      seat:,
      legislator: create(:legislator, sway_locale: other_locale)
    )

    expect(term).not_to be_valid
    expect(term.errors[:seat]).to be_present
  end
end
