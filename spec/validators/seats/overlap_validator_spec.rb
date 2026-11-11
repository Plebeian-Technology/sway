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
end
