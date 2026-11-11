# frozen_string_literal: true

require "rails_helper"

RSpec.describe ScoreRecomputeService do
  describe ".classify (the single normative classifier)" do
    it "classifies matching FOR/FOR as agreed" do
      expect(ScoreRecomputeService.classify("FOR", "FOR")).to eq(:agreed)
    end

    it "classifies matching AGAINST/AGAINST as agreed" do
      expect(ScoreRecomputeService.classify("AGAINST", "AGAINST")).to eq(:agreed)
    end

    it "classifies opposing FOR/AGAINST as disagreed" do
      expect(ScoreRecomputeService.classify("FOR", "AGAINST")).to eq(:disagreed)
    end

    it "classifies a blank legislator vote as no_legislator_vote" do
      expect(ScoreRecomputeService.classify("FOR", nil)).to eq(:no_legislator_vote)
    end

    # An ABSTAIN vote counts as legislator_abstained and nothing else — NOT
    # also disagreed. A deliberate change from the older
    # Scoreable#update_agreeable_score, which counted it twice.
    it "classifies an ABSTAIN legislator vote as legislator_abstained only (D-WS2-a)" do
      expect(ScoreRecomputeService.classify("FOR", "ABSTAIN")).to eq(:legislator_abstained)
      expect(ScoreRecomputeService.classify("AGAINST", "ABSTAIN")).to eq(:legislator_abstained)
    end
  end

  describe ".recompute_bill!" do
    it "recomputes BillScore for/against absolutely from user_votes" do
      sway_locale = create(:sway_locale)
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      create(:legislator_term, legislator:, district:)
      user_for = create(:user)
      user_against = create(:user)
      create(:user_legislator, user: user_for, legislator:)
      create(:user_legislator, user: user_against, legislator:)
      bill = create(:bill, sway_locale:, legislator:)
      create(:user_vote, user: user_for, bill:, support: LegislatorVote::Support::FOR)
      create(:user_vote, user: user_against, bill:, support: LegislatorVote::Support::AGAINST)

      ScoreRecomputeService.recompute_bill!(bill)

      bill_score = BillScore.find_by!(bill:)
      expect(bill_score.for).to eql(1)
      expect(bill_score.against).to eql(1)
    end

    # COUNT(DISTINCT user_votes.id): when two of a user's active legislators sit
    # in the same district, that user's single vote must still count once in the
    # district tally.
    it "counts a vote once even when the voter has two legislators in the same district" do
      sway_locale = create(:sway_locale)
      district = create(:district, sway_locale:)
      legislator1 = create(:legislator, district:)
      create(:legislator_term, legislator: legislator1, district:)
      legislator2 = create(:legislator, district:)
      create(:legislator_term, legislator: legislator2, district:)
      user = create(:user)
      create(:user_legislator, user:, legislator: legislator1)
      create(:user_legislator, user:, legislator: legislator2)
      bill = create(:bill, sway_locale:, legislator: legislator1)
      create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)

      ScoreRecomputeService.recompute_bill!(bill)

      bill_score = BillScore.find_by!(bill:)
      bsd = BillScoreDistrict.find_by!(bill_score:, district:)
      expect(bsd.for).to eql(1)
      expect(bsd.against).to eql(0)
    end
  end

  # The agreement tallies count only ACTIVE user_legislators, in four
  # separate places — this example checks it against the database, so
  # dropping `active: true` anywhere fails a spec.
  describe "active user_legislator filter (D-WS2-b)" do
    it "excludes a user with an inactive user_legislator from LDS and LLS while their raw vote still counts in BillScore" do
      sway_locale = create(:sway_locale)
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      legislator_term = create(:legislator_term, legislator:, district:)
      active_user = create(:user)
      inactive_user = create(:user)
      create(:user_legislator, user: active_user, legislator:, active: true)
      create(:user_legislator, user: inactive_user, legislator:, active: false)
      bill = create(:bill, sway_locale:, legislator:)
      create(:legislator_vote, bill:, legislator:, support: LegislatorVote::Support::FOR)
      create(:user_vote, user: active_user, bill:, support: LegislatorVote::Support::FOR)
      create(:user_vote, user: inactive_user, bill:, support: LegislatorVote::Support::FOR)

      ScoreRecomputeService.recompute_bill!(bill)
      ScoreRecomputeService.recompute_legislator!(legislator_term)

      # Both votes count in the raw locale-wide BillScore tally...
      expect(BillScore.find_by!(bill:).for).to eql(2)

      # ...but only the ACTIVE constituent counts toward the agreement totals.
      lds = LegislatorDistrictScore.find_by!(legislator_term:)
      expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([1, 0, 0, 0])

      lls = LegislatorLocaleScore.find_by!(legislator_term:)
      expect([lls.count_agreed, lls.count_disagreed, lls.count_no_legislator_vote, lls.count_legislator_abstained]).to eql([1, 0, 0, 0])
    end
  end

  # tally_agreement counts only bills whose date falls inside the term being
  # scored. This filter is the trickiest part of the scoring code.
  describe "term-window bill-date attribution" do
    it "attributes a 2024-session bill to the 118th term and a 2025-session bill to the 119th term" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      term_118 = create(:legislator_term, legislator:, district:, term_start_year: 2023, term_end_year: 2025)
      term_119 = create(:legislator_term, legislator:, district:, term_start_year: 2025, term_end_year: 2027)
      user = create(:user)
      create(:user_legislator, user:, legislator:)
      session_118 = create(:legislative_session, :prior, sway_locale:)
      bill_2024 =
        create(
          :bill,
          sway_locale:,
          legislator:,
          legislative_session: session_118,
          introduced_date_time_utc: Time.zone.local(2024, 5, 1),
          scheduled_release_date_utc: Date.new(2024, 5, 1)
        )
      bill_2025 =
        create(
          :bill,
          sway_locale:,
          legislator:,
          introduced_date_time_utc: Time.zone.local(2025, 3, 1),
          scheduled_release_date_utc: Date.new(2025, 3, 1)
        )
      create(:user_vote, user:, bill: bill_2024, support: LegislatorVote::Support::FOR)
      create(:user_vote, user:, bill: bill_2025, support: LegislatorVote::Support::FOR)

      ScoreRecomputeService.recompute_legislator_district!(term_118)
      ScoreRecomputeService.recompute_legislator_district!(term_119)

      lds_118 = LegislatorDistrictScore.find_by!(legislator_term: term_118)
      expect([lds_118.count_agreed, lds_118.count_disagreed, lds_118.count_no_legislator_vote, lds_118.count_legislator_abstained]).to eql([0, 0, 1, 0])

      lds_119 = LegislatorDistrictScore.find_by!(legislator_term: term_119)
      expect([lds_119.count_agreed, lds_119.count_disagreed, lds_119.count_no_legislator_vote, lds_119.count_legislator_abstained]).to eql([0, 0, 1, 0])
    end

    it "recompute for the current term leaves an ended term's LegislatorDistrictScore row byte-identical (freeze, R3)" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      prior_term = create(:legislator_term, legislator:, district:, term_start_year: 2023, term_end_year: 2025)
      current_term = create(:legislator_term, legislator:, district:, term_start_year: 2025, term_end_year: 2027)
      user = create(:user)
      create(:user_legislator, user:, legislator:)
      session_prior = create(:legislative_session, :prior, sway_locale:)
      prior_bill =
        create(
          :bill,
          sway_locale:,
          legislator:,
          legislative_session: session_prior,
          introduced_date_time_utc: Time.zone.local(2024, 5, 1),
          scheduled_release_date_utc: Date.new(2024, 5, 1)
        )
      create(:user_vote, user:, bill: prior_bill, support: LegislatorVote::Support::FOR)

      ScoreRecomputeService.recompute_legislator_district!(prior_term)
      prior_snapshot = LegislatorDistrictScore.find_by!(legislator_term: prior_term).attributes.except("updated_at")

      # A new bill and vote fall inside the CURRENT term's window. A legislator
      # vote only ever recomputes the CURRENT term, so the finished term is
      # never handed back in and its row must stay untouched.
      current_bill =
        create(
          :bill,
          sway_locale:,
          legislator:,
          introduced_date_time_utc: Time.zone.local(2025, 4, 1),
          scheduled_release_date_utc: Date.new(2025, 4, 1)
        )
      create(:user_vote, user:, bill: current_bill, support: LegislatorVote::Support::AGAINST)
      ScoreRecomputeService.recompute_legislator_district!(current_term)

      expect(LegislatorDistrictScore.find_by!(legislator_term: prior_term).attributes.except("updated_at")).to eql(prior_snapshot)

      current_row = LegislatorDistrictScore.find_by!(legislator_term: current_term)
      expect([current_row.count_agreed, current_row.count_disagreed, current_row.count_no_legislator_vote, current_row.count_legislator_abstained]).to eql([0, 0, 1, 0])
    end

    it "recompute_user_legislator! for a late vote on an ended term's bill updates that ended term's UserLegislatorTermScore row" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      prior_term = create(:legislator_term, legislator:, district:, term_start_year: 2023, term_end_year: 2025)
      create(:legislator_term, legislator:, district:, term_start_year: 2025, term_end_year: 2027)
      user = create(:user)
      user_legislator = create(:user_legislator, user:, legislator:)
      session_prior = create(:legislative_session, :prior, sway_locale:)
      prior_bill =
        create(
          :bill,
          sway_locale:,
          legislator:,
          legislative_session: session_prior,
          introduced_date_time_utc: Time.zone.local(2024, 5, 1),
          scheduled_release_date_utc: Date.new(2024, 5, 1)
        )
      create(:user_vote, user:, bill: prior_bill, support: LegislatorVote::Support::FOR)

      ScoreRecomputeService.recompute_user_legislator!(user_legislator, prior_term)

      ults = UserLegislatorTermScore.find_by!(user_legislator:, legislator_term: prior_term)
      expect([ults.count_agreed, ults.count_disagreed, ults.count_no_legislator_vote, ults.count_legislator_abstained]).to eql([0, 0, 1, 0])
    end

    # @lat: [[current-legislator-term#A date before every term this person served has no term]]
    it "counts a bill dated before every term toward none of them" do
      sway_locale = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      term = create(:legislator_term, legislator:, district:, term_start_year: 2025, term_end_year: 2027)
      user = create(:user)
      create(:user_legislator, user:, legislator:)
      ancient_bill =
        create(
          :bill,
          sway_locale:,
          legislator:,
          introduced_date_time_utc: Time.zone.local(2010, 1, 1),
          scheduled_release_date_utc: Date.new(2010, 1, 1)
        )
      create(:user_vote, user:, bill: ancient_bill, support: LegislatorVote::Support::FOR)

      ScoreRecomputeService.recompute_legislator_district!(term)

      row = LegislatorDistrictScore.find_by!(legislator_term: term)
      expect([row.count_agreed, row.count_disagreed, row.count_no_legislator_vote, row.count_legislator_abstained])
        .to eql([0, 0, 0, 0])
    end

    # The acceptance case. Baltimore publishes no term dates, so a successor
    # seeded today takes a term beginning 5 December 2024. The predecessor
    # keeps the earlier part, so no vote is lost — only moved off the wrong
    # person.
    it "does not score a successor on a bill decided before they took the seat" do
      sway_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
      district = create(:district, sway_locale:)
      predecessor = create(:legislator, district:, external_id: "baltimore-district-1|mark-parker")
      successor = create(:legislator, district:, external_id: "baltimore-district-1|new-member")
      predecessor_term = create(
        :legislator_term, legislator: predecessor, district:,
        term_start_year: 2024, term_end_year: 2028, ended_on: Date.new(2026, 6, 1),
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )
      successor_term = create(
        :legislator_term, legislator: successor, district:,
        term_start_year: 2024, term_end_year: 2028, began_on: Date.new(2026, 6, 1),
        began_on_source: LegislatorTerm::DateSource::OBSERVED
      )
      user = create(:user)
      create(:user_legislator, user:, legislator: predecessor)
      create(:user_legislator, user:, legislator: successor)
      earlier_bill = create(
        :bill, sway_locale:, legislator: predecessor,
        introduced_date_time_utc: Time.zone.local(2025, 4, 1),
        scheduled_release_date_utc: Date.new(2025, 4, 1)
      )
      create(:user_vote, user:, bill: earlier_bill, support: LegislatorVote::Support::FOR)

      ScoreRecomputeService.recompute_legislator_district!(successor_term)
      ScoreRecomputeService.recompute_legislator_district!(predecessor_term)

      successor_row = LegislatorDistrictScore.find_by!(legislator_term: successor_term)
      expect(successor_row.count_no_legislator_vote).to eq(0)

      predecessor_row = LegislatorDistrictScore.find_by!(legislator_term: predecessor_term)
      expect(predecessor_row.count_no_legislator_vote).to eq(1)
    end
  end

  describe "dual boundary checks (TASK-iwxrj.26: Refactor ScoreRecomputeService boundaries)" do
    let(:sway_locale) { create(:sway_locale, city: "congress", state: "congress", country: "united_states") }
    let(:district) { create(:district, sway_locale:) }
    let(:legislator) { create(:legislator, district:) }
    let(:user) { create(:user) }

    before do
      create(:user_legislator, user:, legislator:)
    end

    it "does not tally votes when a bill is introduced before a mid-session appointee's term began_on even if voted during term" do
      appointee_term = create(
        :legislator_term,
        legislator:,
        district:,
        term_start_year: 2025,
        term_end_year: 2027,
        began_on: Date.new(2025, 6, 1),
        began_on_source: LegislatorTerm::DateSource::OBSERVED
      )
      bill = create(
        :bill,
        sway_locale:,
        legislator:,
        introduced_date_time_utc: Time.zone.local(2025, 3, 1),
        house_vote_date_time_utc: Time.zone.local(2025, 7, 1),
        scheduled_release_date_utc: Date.new(2025, 7, 1)
      )
      create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)
      create(:legislator_vote, bill:, legislator:, support: LegislatorVote::Support::FOR)

      tally = ScoreRecomputeService.send(:tally_agreement, [user.id], appointee_term, sway_locale)
      expect(tally[:count_agreed]).to eq(0)
      expect(tally[:count_disagreed]).to eq(0)
      expect(tally[:count_no_legislator_vote]).to eq(0)
      expect(tally[:count_legislator_abstained]).to eq(0)
    end

    it "does not tally votes when a bill is introduced outside session boundaries" do
      session = create(
        :legislative_session,
        sway_locale:,
        start_date: Date.new(2025, 1, 3),
        end_date: Date.new(2025, 6, 30),
        active: true
      )
      term = create(
        :legislator_term,
        legislator:,
        district:,
        term_start_year: 2025,
        term_end_year: 2027
      )
      # Introduced outside session boundaries (after session.end_date, but within legislator term)
      outside_bill = create(
        :bill,
        sway_locale:,
        legislative_session: session,
        legislator:,
        introduced_date_time_utc: Time.zone.local(2025, 8, 1),
        scheduled_release_date_utc: Date.new(2025, 8, 1)
      )
      create(:user_vote, user:, bill: outside_bill, support: LegislatorVote::Support::FOR)
      create(:legislator_vote, bill: outside_bill, legislator:, support: LegislatorVote::Support::FOR)

      tally = ScoreRecomputeService.send(:tally_agreement, [user.id], term, sway_locale)
      expect(tally[:count_agreed]).to eq(0)
      expect(tally[:count_disagreed]).to eq(0)

      # Introduced inside session boundaries
      inside_bill = create(
        :bill,
        sway_locale:,
        legislative_session: session,
        legislator:,
        introduced_date_time_utc: Time.zone.local(2025, 5, 1),
        scheduled_release_date_utc: Date.new(2025, 5, 1)
      )
      create(:user_vote, user:, bill: inside_bill, support: LegislatorVote::Support::FOR)
      create(:legislator_vote, bill: inside_bill, legislator:, support: LegislatorVote::Support::FOR)

      inside_tally = ScoreRecomputeService.send(:tally_agreement, [user.id], term, sway_locale)
      expect(inside_tally[:count_agreed]).to eq(1)
    end

    it "enforces inclusive session start_date and end_date boundaries and term began_on boundaries" do
      session = create(
        :legislative_session,
        sway_locale:,
        name: "119th Congress Boundary",
        start_date: Date.new(2025, 1, 3),
        end_date: Date.new(2027, 1, 2),
        active: true
      )
      appointee_term = create(
        :legislator_term,
        legislator:,
        district:,
        term_start_year: 2025,
        term_end_year: 2027,
        began_on: Date.new(2025, 6, 1),
        ended_on: Date.new(2027, 1, 3),
        began_on_source: LegislatorTerm::DateSource::OBSERVED,
        ended_on_source: LegislatorTerm::DateSource::OBSERVED
      )

      before_began_bill = create(
        :bill,
        sway_locale:,
        legislative_session: session,
        legislator:,
        introduced_date_time_utc: Time.zone.local(2025, 5, 31, 23, 59, 59),
        scheduled_release_date_utc: Date.new(2025, 6, 15)
      )
      create(:user_vote, user:, bill: before_began_bill, support: LegislatorVote::Support::FOR)
      create(:legislator_vote, bill: before_began_bill, legislator:, support: LegislatorVote::Support::FOR)
      expect(ScoreRecomputeService.send(:tally_agreement, [user.id], appointee_term, sway_locale)[:count_agreed]).to eq(0)

      exact_began_bill = create(
        :bill,
        sway_locale:,
        legislative_session: session,
        legislator:,
        introduced_date_time_utc: Time.zone.local(2025, 6, 1, 0, 0, 0),
        scheduled_release_date_utc: Date.new(2025, 6, 16)
      )
      create(:user_vote, user:, bill: exact_began_bill, support: LegislatorVote::Support::FOR)
      create(:legislator_vote, bill: exact_began_bill, legislator:, support: LegislatorVote::Support::FOR)
      expect(ScoreRecomputeService.send(:tally_agreement, [user.id], appointee_term, sway_locale)[:count_agreed]).to eq(1)

      exact_end_bill = create(
        :bill,
        sway_locale:,
        legislative_session: session,
        legislator:,
        introduced_date_time_utc: Time.zone.local(2027, 1, 2, 23, 59, 59),
        scheduled_release_date_utc: Date.new(2027, 1, 2)
      )
      create(:user_vote, user:, bill: exact_end_bill, support: LegislatorVote::Support::FOR)
      create(:legislator_vote, bill: exact_end_bill, legislator:, support: LegislatorVote::Support::FOR)
      expect(ScoreRecomputeService.send(:tally_agreement, [user.id], appointee_term, sway_locale)[:count_agreed]).to eq(2)

      after_end_bill = create(
        :bill,
        sway_locale:,
        legislative_session: session,
        legislator:,
        introduced_date_time_utc: Time.zone.local(2027, 1, 3, 0, 0, 0),
        scheduled_release_date_utc: Date.new(2027, 1, 3)
      )
      create(:user_vote, user:, bill: after_end_bill, support: LegislatorVote::Support::FOR)
      create(:legislator_vote, bill: after_end_bill, legislator:, support: LegislatorVote::Support::FOR)
      expect(ScoreRecomputeService.send(:tally_agreement, [user.id], appointee_term, sway_locale)[:count_agreed]).to eq(2)
    end
  end
end
