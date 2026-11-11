# frozen_string_literal: true

require "rails_helper"

RSpec.describe LegislatorTerm, "seat occupancy write guards" do
  let(:locale) { create(:sway_locale, :congress) }
  let(:district) { create(:district, sway_locale: locale, name: "MD0") }
  let(:seat) do
    Seat.create!(district:, seat_identifier: "published-fixture-office", title: "Fixture Senator", chamber: "Senate")
  end

  def term_for(legislator, began_on:, ended_on:)
    create(:legislator_term, legislator:, district:, seat:,
      began_on:, ended_on:,
      began_on_source: LegislatorTerm::DateSource::PUBLISHED,
      ended_on_source: LegislatorTerm::DateSource::PUBLISHED,
      term_start_year: began_on.year, term_end_year: ended_on.year)
  end

  # @lat: [[seat-occupancy-adversarial-tests#Seat occupancy adversarial tests#Nonpositive service intervals refuse]]
  it "rejects zero-length and reversed intervals on a resolved seat" do
    legislator = create(:legislator, sway_locale: locale)
    [Date.new(2026, 5, 1), Date.new(2026, 4, 30)].each do |ended_on|
      expect { term_for(legislator, began_on: Date.new(2026, 5, 1), ended_on:) }
        .to raise_error(ActiveRecord::RecordInvalid)
    end
    expect(LegislatorTerm.count).to eq(0)
  end

  # @lat: [[seat-occupancy-adversarial-tests#Seat occupancy adversarial tests#Direct interval changes roll back on overlap]]
  it "rolls back a direct date change that would overlap an adjacent successor" do
    predecessor = term_for(create(:legislator, sway_locale: locale), began_on: Date.new(2026, 1, 1), ended_on: Date.new(2026, 5, 1))
    term_for(create(:legislator, sway_locale: locale), began_on: Date.new(2026, 5, 1), ended_on: Date.new(2026, 9, 1))

    expect { predecessor.update_columns(ended_on: Date.new(2026, 8, 1)) }
      .to raise_error(Seats::OverlapValidator::OverlapError)
    expect(predecessor.reload.ended_on).to eq(Date.new(2026, 5, 1))
  end

  # @lat: [[seat-occupancy-adversarial-tests#Seat occupancy adversarial tests#Normal writes retain a resolved seat]]
  it "refuses clearing an established seat through an ordinary update" do
    term = term_for(create(:legislator, sway_locale: locale), began_on: Date.new(2026, 1, 1), ended_on: Date.new(2026, 5, 1))

    expect { term.update!(seat: nil) }.to raise_error(ActiveRecord::RecordInvalid)
    expect(term.reload.seat_id).to eq(seat.id)
  end

  # @lat: [[seat-occupancy-adversarial-tests#Seat occupancy adversarial tests#Direct writes retain a resolved seat]]
  it "refuses clearing an established seat through update_columns" do
    term = term_for(create(:legislator, sway_locale: locale), began_on: Date.new(2026, 1, 1), ended_on: Date.new(2026, 5, 1))

    expect { term.update_columns(seat_id: nil) }.to raise_error(Seats::UnresolvedSeatError)
    expect(term.reload.seat_id).to eq(seat.id)
  end
  # @lat: [[seat-occupancy-adversarial-tests#Seat occupancy adversarial tests#Direct person changes retain locale ownership]]
  it "rolls back a direct reassignment to a person in another locale" do
    person = create(:legislator, sway_locale: locale)
    term = term_for(person, began_on: Date.new(2026, 1, 1), ended_on: Date.new(2026, 5, 1))
    other_locale = create(:sway_locale, :maryland)
    other_person = create(:legislator, sway_locale: other_locale)

    expect { term.update_columns(legislator_id: other_person.id) }
      .to raise_error(Seats::UnresolvedSeatError)
    expect(term.reload.legislator_id).to eq(person.id)
  end
end
