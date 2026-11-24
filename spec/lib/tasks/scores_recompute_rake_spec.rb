# frozen_string_literal: true

require "rails_helper"
require "rake"

# @lat: [[scores-recompute-rake-history#The term-keyed API fix]]
RSpec.describe "sway:scores:recompute_all" do
  include_context "with a voter minimum of one"

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:scores:recompute_all")
  end

  before { Rake::Task["sway:scores:recompute_all"].reenable }

  it "recomputes current-term legislator-side and user-side scores from source" do
    sway_locale = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)
    current_term = create(:legislator_term, legislator:, district:, term_start_year: 2025, term_end_year: 2027)
    user = create(:user)
    user_legislator = create(:user_legislator, user:, legislator:, active: true)
    bill =
      create(
        :bill,
        sway_locale:,
        legislator:,
        introduced_date_time_utc: Time.zone.local(2025, 4, 1),
        scheduled_release_date_utc: Date.new(2025, 4, 1)
      )
    create(:legislator_vote, legislator:, bill:, legislator_term: current_term, support: LegislatorVote::Support::FOR)
    create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)

    Rake::Task["sway:scores:recompute_all"].invoke

    expect(LegislatorDistrictScore.find_by!(legislator_term: current_term).count_agreed).to eq(1)
    expect(LegislatorLocaleScore.find_by!(legislator_term: current_term).count_agreed).to eq(1)
    ults = UserLegislatorTermScore.find_by!(user_legislator:, legislator_term: current_term)
    expect(ults.count_agreed).to eq(1)
  end

  # Replaces "leaves an ended term's frozen legislator-side row untouched (R3)".
  # The number is rebuilt from the votes, so a row carrying something the votes
  # do not support is corrected rather than preserved.
  it "rebuilds an ended term's legislator-side row from source" do
    sway_locale = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)
    prior_term = create(:legislator_term, legislator:, district:, term_start_year: 2023, term_end_year: 2025)
    create(:legislator_term, legislator:, district:, term_start_year: 2025, term_end_year: 2027)
    create(:user_legislator, user: create(:user), legislator:, active: true)

    LegislatorDistrictScore.create!(
      legislator_term: prior_term,
      count_agreed: 99, count_disagreed: 7, count_no_legislator_vote: 3, count_legislator_abstained: 1
    )

    Rake::Task["sway:scores:recompute_all"].invoke

    rebuilt = LegislatorDistrictScore.find_by!(legislator_term: prior_term)
    expect(rebuilt.count_agreed).to eq(0)
    expect(rebuilt.count_disagreed).to eq(0)
  end

  # The case that was never repaired at all: Legislator.serving joins the active
  # term, so somebody whose only term has finished was skipped entirely. Their
  # votes are recorded, so the number was always derivable — nothing derived it,
  # and the History tab showed the gap.
  it "repairs a member who has left, whose only term has ended" do
    sway_locale = create(:sway_locale, :congress)
    district = create(:district, sway_locale:)
    departed = create(:legislator, district:)
    ended_term = create(
      :legislator_term, legislator: departed, district:, term_start_year: 2021, term_end_year: 2023
    )
    # @lat: [[scores-recompute-rake-history#Rebuilding an ended term's row instead of preserving it#What the departed-member spec checks]]
    still_here = create(:user)
    create(:user_legislator, user: still_here, legislator: departed, active: true)
    moved_on = create(:user)
    ended_link = create(:user_legislator, user: moved_on, legislator: departed, active: false)

    session = create(
      :legislative_session,
      sway_locale:,
      name: "117th Congress",
      start_date: Date.new(2021, 1, 3),
      end_date: Date.new(2023, 1, 3),
      active: false
    )
    bill = create(
      :bill,
      sway_locale:,
      legislative_session: session,
      legislator: departed,
      introduced_date_time_utc: Time.zone.local(2022, 4, 1),
      scheduled_release_date_utc: Date.new(2022, 4, 1)
    )
    create(:legislator_vote, legislator: departed, bill:, legislator_term: ended_term, support: LegislatorVote::Support::FOR)
    create(:user_vote, user: still_here, bill:, support: LegislatorVote::Support::FOR)
    create(:user_vote, user: moved_on, bill:, support: LegislatorVote::Support::FOR)

    expect(Legislator.serving).not_to include(departed)

    Rake::Task["sway:scores:recompute_all"].invoke

    expect(LegislatorLocaleScore.find_by!(legislator_term: ended_term).count_agreed).to eq(1)
    expect(LegislatorDistrictScore.find_by!(legislator_term: ended_term)).not_to be_nil
    expect(
      UserLegislatorTermScore.find_by!(user_legislator: ended_link, legislator_term: ended_term).count_agreed
    ).to eq(1)
  end

  it "skips a legislator with no term at all without raising (SPEC boundary)" do
    sway_locale = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
    district = create(:district, sway_locale:)
    # @lat: [[scores-recompute-rake-history#Rebuilding an ended term's row instead of preserving it#Why the "no term at all" boundary case needs an old term to rule out]]
    legislator = create(:legislator, district:)
    create(:user_legislator, user: create(:user), legislator:, active: true)

    expect { Rake::Task["sway:scores:recompute_all"].invoke }.not_to raise_error
    expect(LegislatorLocaleScore.count).to eq(0)
    expect(LegislatorDistrictScore.count).to eq(0)
  end
end
