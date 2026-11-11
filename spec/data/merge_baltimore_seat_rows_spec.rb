# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260801000001_merge_baltimore_seat_rows")

# Rebuilds the shape Baltimore is in — two rows per person, both in
# office, one holding every vote and user link and the other holding nothing —
# and checks the migration leaves one row per seat with its history intact.
RSpec.describe "MergeBaltimoreSeatRows data migration", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:baltimore) do
    create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
  end
  let(:district_one) { create(:district, name: "MD1", sway_locale: baltimore) }
  let(:citywide) { create(:district, name: "MD0", sway_locale: baltimore) }

  # The pair Baltimore actually holds: an empty row named after the seat, and the
  # row the votes and links are on, named after the person.
  def seat_pair(first_name:, last_name:, seat_key:, district:, title:)
    empty = create(:legislator, sway_locale: baltimore, external_id: seat_key,
      first_name:, last_name:)
    create(:legislator_term, legislator: empty, district:, title:,
      term_start_year: 2024, term_end_year: 2028)

    keeper = create(:legislator, sway_locale: baltimore,
      external_id: "#{first_name}-#{last_name}-2024".downcase,
      first_name:, last_name:)
    keeper_term = create(:legislator_term, legislator: keeper, district:, title: nil,
      term_start_year: 2024, term_end_year: 2028)

    [empty, keeper, keeper_term]
  end

  around { |example| travel_to(Date.new(2026, 8, 1)) { example.run } }

  it "keeps the row holding the votes and gives it the seat's name" do
    empty, keeper, _term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    bill = create(:bill, sway_locale: baltimore)
    create(:legislator_vote, legislator: keeper, bill:)

    MergeBaltimoreSeatRows.new.up

    expect(Legislator.where(id: empty.id)).to be_empty
    expect(keeper.reload.external_id).to eq("baltimore-district-1")
    expect(keeper.legislator_votes.count).to eq(1)
  end

  it "leaves one person in office per seat, not two" do
    seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")

    expect { MergeBaltimoreSeatRows.new.up }
      .to change { Legislator.serving.where(sway_locale: baltimore).count }.from(2).to(1)
  end

  # A term's title is the one field the seeder never writes twice, and only the
  # empty rows carry one. Losing it strips "Mayor" and "Council Member" off every
  # Baltimore card.
  it "carries the title across before deleting the empty row" do
    _empty, _keeper, keeper_term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")

    MergeBaltimoreSeatRows.new.up

    expect(keeper_term.reload.title).to eq("Council Member")
  end

  # The Mayor and the Council President both sit under the stand-in district MD0,
  # so the rewriter tells them apart by title — which only works because the
  # title comes across first.
  it "names the two citywide offices by their office, not by a district" do
    _empty, mayor, _term = seat_pair(first_name: "Brandon", last_name: "Scott",
      seat_key: "baltimore-mayor", district: citywide, title: "Mayor")
    _empty2, president, _term2 = seat_pair(first_name: "Zeke", last_name: "Cohen",
      seat_key: "baltimore-council-president", district: citywide, title: "Council President")

    MergeBaltimoreSeatRows.new.up

    expect(mayor.reload.external_id).to eq("baltimore-mayor")
    expect(president.reload.external_id).to eq("baltimore-council-president")
  end

  it "keeps every user's link to their representative" do
    _empty, keeper, _term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    user = create(:user)
    link = create(:user_legislator, user:, legislator: keeper, active: true)

    MergeBaltimoreSeatRows.new.up

    expect(link.reload).to have_attributes(legislator_id: keeper.id, active: true)
  end

  # The seat's previous holder is a different person with their own votes. Their
  # term has ended, so they are not in office and nothing here touches them.
  it "leaves the person who held the seat before alone" do
    _empty, _keeper, _term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    departed = create(:legislator, sway_locale: baltimore, external_id: "nick-mosby-2020",
      first_name: "Nick", last_name: "Mosby")
    create(:legislator_term, legislator: departed, district: district_one,
      term_start_year: 2020, term_end_year: 2024)

    MergeBaltimoreSeatRows.new.up

    expect(departed.reload.external_id).to eq("nick-mosby-2020")
    expect(departed.legislator_terms.count).to eq(1)
  end

  # Deleting a row that holds anything would lose it. The check runs against the
  # database in front of it, not against what was measured on a copy.
  it "refuses to delete a seat row that holds a vote" do
    empty, _keeper, _term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    bill = create(:bill, sway_locale: baltimore)
    create(:legislator_vote, legislator: empty, bill:)

    MergeBaltimoreSeatRows.new.up

    expect(Legislator.where(id: empty.id)).to be_present
  end

  it "changes nothing on a second run" do
    seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    MergeBaltimoreSeatRows.new.up

    expect { MergeBaltimoreSeatRows.new.up }
      .not_to(change { Legislator.where(sway_locale: baltimore).pluck(:id, :external_id).sort })
  end

  it "leaves a seat that already has only one row alone" do
    lone = create(:legislator, sway_locale: baltimore, external_id: "baltimore-district-1",
      first_name: "Mark", last_name: "Parker")
    create(:legislator_term, legislator: lone, district: district_one, title: "Council Member",
      term_start_year: 2024, term_end_year: 2028)

    expect { MergeBaltimoreSeatRows.new.up }.not_to(change { Legislator.count })
    expect(lone.reload.external_id).to eq("baltimore-district-1")
  end
end
