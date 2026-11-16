# frozen_string_literal: true

require "rails_helper"

RSpec.describe Seats::OverlapValidator do
  let(:sway_locale) { create(:sway_locale, :congress) }
  let(:district) { create(:district, sway_locale:, name: "MD0") }
  let(:seat) do
    Seat.create!(
      district:,
      seat_identifier: "md-senate-class-1",
      title: "United States Senator",
      chamber: "Senate"
    )
  end

  it "allows adjacent service intervals for one seat" do
    predecessor = create(:legislator, sway_locale:)
    successor = create(:legislator, sway_locale:)
    create(
      :legislator_term,
      legislator: predecessor,
      district:,
      seat:,
      term_start_year: 2023,
      term_end_year: 2025
    )
    successor_term = build(
      :legislator_term,
      legislator: successor,
      district:,
      seat:,
      term_start_year: 2025,
      term_end_year: 2027
    )

    expect { described_class.validate_term!(successor_term) }.not_to raise_error
    expect(successor_term).to be_valid
  end

  it "rejects overlapping service intervals for one seat" do
    predecessor = create(:legislator, sway_locale:)
    successor = create(:legislator, sway_locale:)
    create(
      :legislator_term,
      legislator: predecessor,
      district:,
      seat:,
      term_start_year: 2023,
      term_end_year: 2027
    )
    overlapping = build(
      :legislator_term,
      legislator: successor,
      district:,
      seat:,
      term_start_year: 2025,
      term_end_year: 2029
    )

    expect { described_class.validate_term!(overlapping) }
      .to raise_error(Seats::OverlapValidator::OverlapError)
    expect(overlapping).not_to be_valid
  end

  it "allows simultaneous terms on distinct seats in the same district" do
    first = seat
    second = Seat.create!(
      district:,
      seat_identifier: "md-senate-class-3",
      title: "United States Senator",
      chamber: "Senate"
    )
    create(
      :legislator_term,
      legislator: create(:legislator, sway_locale:),
      district:,
      seat: first,
      term_start_year: 2023,
      term_end_year: 2029
    )
    concurrent = build(
      :legislator_term,
      legislator: create(:legislator, sway_locale:),
      district:,
      seat: second,
      term_start_year: 2025,
      term_end_year: 2031
    )

    expect { described_class.validate_term!(concurrent) }.not_to raise_error
  end

  it "rolls back update_columns when it would create overlap" do
    predecessor = create(:legislator, sway_locale:)
    successor = create(:legislator, sway_locale:)
    create(
      :legislator_term,
      legislator: predecessor,
      district:,
      seat:,
      term_start_year: 2023,
      term_end_year: 2025
    )
    successor_term = create(
      :legislator_term,
      legislator: successor,
      district:,
      seat:,
      term_start_year: 2025,
      term_end_year: 2027
    )

    expect { successor_term.update_columns(term_start_year: 2023) }
      .to raise_error(Seats::OverlapValidator::OverlapError)
    expect(successor_term.reload.term_start_year).to eq(2025)
  end

  it "raises UnresolvedSeatError when seat_id is blank or does not exist" do
    legislator = create(:legislator, sway_locale:)

    unseated_new = build(:legislator_term, legislator:, district:, seat: nil)
    expect { described_class.validate_term!(unseated_new) }
      .to raise_error(Seats::UnresolvedSeatError, "Term new has no persisted seat identity")

    missing_seat_new = build(:legislator_term, legislator:, district:, seat_id: 999_999_999)
    expect { described_class.validate_term!(missing_seat_new) }
      .to raise_error(Seats::UnresolvedSeatError, "Term new has no persisted seat identity")

    persisted_term = create(:legislator_term, legislator:, district:, seat:)
    persisted_term.seat_id = 999_999_999
    expect { described_class.validate_term!(persisted_term) }
      .to raise_error(Seats::UnresolvedSeatError, "Term #{persisted_term.id} has no persisted seat identity")
  end

  it "raises UnresolvedSeatError when seat district or legislator locale mismatches" do
    other_district = create(:district, sway_locale:, name: "MD1")
    legislator = create(:legislator, sway_locale:)
    wrong_district_term = build(:legislator_term, legislator:, district: other_district, seat:)

    expect { described_class.validate_term!(wrong_district_term) }
      .to raise_error(Seats::UnresolvedSeatError, /does not belong to term district/)

    other_locale = create(:sway_locale, :maryland)
    other_legislator = create(:legislator, sway_locale: other_locale)
    wrong_locale_term = build(:legislator_term, legislator: other_legislator, district:, seat:)

    expect { described_class.validate_term!(wrong_locale_term) }
      .to raise_error(Seats::UnresolvedSeatError, /does not belong to term's legislator locale/)
  end

  it "raises InvalidIntervalError when term ends on or before start or locale calendar is undeclared" do
    legislator = create(:legislator, sway_locale:)
    inverted = build(:legislator_term, legislator:, district:, seat:, term_start_year: 2027, term_end_year: 2025)

    expect { described_class.validate_term!(inverted) }
      .to raise_error(Seats::OverlapValidator::InvalidIntervalError, /must end after it begins/)

    undeclared = create(:sway_locale, city: "undeclared_cal", state: "MD", country: "US")
    undeclared_dist = create(:district, sway_locale: undeclared, name: "MD1")
    undeclared_seat = Seat.create!(district: undeclared_dist, seat_identifier: "u-1", title: "Member", chamber: "Council")
    undeclared_leg = create(:legislator, sway_locale: undeclared, district: undeclared_dist)
    undeclared_term = build(:legislator_term, legislator: undeclared_leg, district: undeclared_dist, seat: undeclared_seat)

    expect { described_class.validate_term!(undeclared_term) }
      .to raise_error(Seats::OverlapValidator::InvalidIntervalError, /no declared calendar for seat occupancy/)
  end
end
