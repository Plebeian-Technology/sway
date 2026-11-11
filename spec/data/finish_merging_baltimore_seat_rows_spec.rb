# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260803000001_finish_merging_baltimore_seat_rows")

# Rebuilds the shape production is really in — the shape
# 20260801000001 was measured against, plus the two kinds of row that appeared
# after that measurement and stopped it merging anything: an all-zero score row
# on the seat term, and a reader linked to both rows for the same person.
RSpec.describe "FinishMergingBaltimoreSeatRows data migration", type: :model do
  include ActiveSupport::Testing::TimeHelpers

  let(:baltimore) do
    create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
  end
  let(:district_one) { create(:district, name: "MD1", sway_locale: baltimore) }
  let(:citywide) { create(:district, name: "MD0", sway_locale: baltimore) }

  # One seat as production holds it: a row named after the seat carrying a score
  # row that counts nothing, and the row named after the person carrying the
  # votes and the links. Returns the seat row, the keeper, and the keeper's term.
  def seat_pair(first_name:, last_name:, seat_key:, district:, title:)
    seat_row = create(:legislator, sway_locale: baltimore, external_id: seat_key,
      first_name:, last_name:)
    seat_term = create(:legislator_term, legislator: seat_row, district:, title:,
      term_start_year: 2024, term_end_year: 2028)
    create(:legislator_locale_score, legislator_term: seat_term)

    keeper = create(:legislator, sway_locale: baltimore,
      external_id: "#{first_name}-#{last_name}-2024".downcase,
      first_name:, last_name:)
    keeper_term = create(:legislator_term, legislator: keeper, district:, title: nil,
      term_start_year: 2024, term_end_year: 2028)

    [seat_row, keeper, keeper_term]
  end

  around { |example| travel_to(Date.new(2026, 8, 3)) { example.run } }

  # The one thing 20260801000001 could not do. Its guard read this score row as
  # something the seat row held and left the seat alone.
  it "merges a seat whose only company is a score row counting no votes" do
    seat_row, keeper, _term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    bill = create(:bill, sway_locale: baltimore)
    create(:legislator_vote, legislator: keeper, bill:)

    FinishMergingBaltimoreSeatRows.new.up

    expect(Legislator.where(id: seat_row.id)).to be_empty
    expect(keeper.reload.external_id).to eq("baltimore-district-1")
    expect(keeper.legislator_votes.count).to eq(1)
  end

  it "leaves one person in office per seat, not two" do
    seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")

    expect { FinishMergingBaltimoreSeatRows.new.up }
      .to change { Legislator.serving.where(sway_locale: baltimore).count }.from(2).to(1)
  end

  # What the reader reported: three representatives listed six times, because
  # both rows for each of them were linked to their account.
  it "leaves a reader linked to both rows with one link, on the row holding the record" do
    seat_row, keeper, _term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    user = create(:user)
    kept = create(:user_legislator, user:, legislator: keeper, active: true)
    copy = create(:user_legislator, user:, legislator: seat_row, active: true)
    create(:user_legislator_term_score, user_legislator: copy,
      legislator_term: seat_row.legislator_terms.first)

    FinishMergingBaltimoreSeatRows.new.up

    expect(UserLegislator.where(user:).pluck(:id)).to eq([kept.id])
    expect(kept.reload).to have_attributes(legislator_id: keeper.id, active: true)
    expect(UserLegislatorTermScore.where(user_legislator_id: copy.id)).to be_empty
  end

  # The reassignment that made these links walks readers one at a time, so a
  # reader can end up on the seat row and nowhere else. Deleting that link would
  # take a representative off their page.
  it "moves a link that exists only on the seat row onto the keeper" do
    seat_row, keeper, _term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    user = create(:user)
    only_link = create(:user_legislator, user:, legislator: seat_row, active: true)

    FinishMergingBaltimoreSeatRows.new.up

    expect(only_link.reload).to have_attributes(legislator_id: keeper.id, active: true)
  end

  it "switches the keeper's link back on when the copy was the live one" do
    seat_row, keeper, _term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    user = create(:user)
    switched_off = create(:user_legislator, user:, legislator: keeper, active: false)
    create(:user_legislator, user:, legislator: seat_row, active: true)

    FinishMergingBaltimoreSeatRows.new.up

    expect(switched_off.reload.active).to be(true)
  end

  it "carries the title across before deleting the seat row" do
    _seat_row, _keeper, keeper_term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")

    FinishMergingBaltimoreSeatRows.new.up

    expect(keeper_term.reload.title).to eq("Council Member")
  end

  # Both citywide offices sit under the stand-in district MD0, so they are told
  # apart by title — which only works because the title comes across first.
  it "names the two citywide offices by their office, not by a district" do
    _seat_row, mayor, _term = seat_pair(first_name: "Brandon", last_name: "Scott",
      seat_key: "baltimore-mayor", district: citywide, title: "Mayor")
    _seat_row2, president, _term2 = seat_pair(first_name: "Zeke", last_name: "Cohen",
      seat_key: "baltimore-council-president", district: citywide, title: "Council President")

    FinishMergingBaltimoreSeatRows.new.up

    expect(mayor.reload.external_id).to eq("baltimore-mayor")
    expect(president.reload.external_id).to eq("baltimore-council-president")
  end

  # The seat's previous holder is a different person with their own votes. Their
  # term has ended, so they are not in office and nothing here touches them.
  it "leaves the person who held the seat before alone" do
    seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    departed = create(:legislator, sway_locale: baltimore, external_id: "nick-mosby-2020",
      first_name: "Nick", last_name: "Mosby")
    create(:legislator_term, legislator: departed, district: district_one,
      term_start_year: 2020, term_end_year: 2024)

    FinishMergingBaltimoreSeatRows.new.up

    expect(departed.reload.external_id).to eq("nick-mosby-2020")
    expect(departed.legislator_terms.count).to eq(1)
  end

  it "refuses to delete a seat row that holds a vote" do
    seat_row, _keeper, _term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    bill = create(:bill, sway_locale: baltimore)
    create(:legislator_vote, legislator: seat_row, bill:)

    FinishMergingBaltimoreSeatRows.new.up

    expect(Legislator.where(id: seat_row.id)).to be_present
  end

  it "refuses to delete a seat row that holds a co-sponsorship" do
    seat_row, _keeper, _term = seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    bill = create(:bill, sway_locale: baltimore)
    create(:bill_cosponsor, bill:, legislator: seat_row)

    FinishMergingBaltimoreSeatRows.new.up

    expect(Legislator.where(id: seat_row.id)).to be_present
  end

  it "changes nothing on a second run" do
    seat_pair(first_name: "Mark", last_name: "Parker",
      seat_key: "baltimore-district-1", district: district_one, title: "Council Member")
    FinishMergingBaltimoreSeatRows.new.up

    expect { FinishMergingBaltimoreSeatRows.new.up }
      .not_to(change { Legislator.where(sway_locale: baltimore).pluck(:id, :external_id).sort })
  end

  it "leaves a seat that already has only one row alone" do
    lone = create(:legislator, sway_locale: baltimore, external_id: "baltimore-district-1",
      first_name: "Mark", last_name: "Parker")
    create(:legislator_term, legislator: lone, district: district_one, title: "Council Member",
      term_start_year: 2024, term_end_year: 2028)

    expect { FinishMergingBaltimoreSeatRows.new.up }.not_to(change { Legislator.count })
    expect(lone.reload.external_id).to eq("baltimore-district-1")
  end
end
