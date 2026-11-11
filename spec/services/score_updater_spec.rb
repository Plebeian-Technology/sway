# frozen_string_literal: true

require "rails_helper"

# A table of cases for what a user vote does. Each checks totals stored
# after ScoreUpdaterService#call recomputes: agreed, disagreed,
# no_legislator_vote, legislator_abstained.
RSpec.describe ScoreUpdaterService do
  describe "#call — the score-write case matrix" do
    it "M-U1: user FOR, legislator FOR → agreed across every aggregate" do
      sway_locale = create(:sway_locale)
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      legislator_term = create(:legislator_term, legislator:, district:)
      user = create(:user)
      user_legislator = create(:user_legislator, user:, legislator:)
      bill = create(:bill, sway_locale:, legislator:)
      create(:legislator_vote, bill:, legislator:, support: LegislatorVote::Support::FOR)
      user_vote = create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)

      ScoreUpdaterService.new(user_vote).call

      bill_score = BillScore.find_by!(bill:)
      expect(bill_score.for).to eql(1)
      expect(bill_score.against).to eql(0)

      bsd = BillScoreDistrict.find_by!(bill_score:, district:)
      expect(bsd.for).to eql(1)
      expect(bsd.against).to eql(0)

      uls = UserLegislatorTermScore.find_by!(user_legislator:, legislator_term:)
      expect([uls.count_agreed, uls.count_disagreed, uls.count_no_legislator_vote, uls.count_legislator_abstained]).to eql([1, 0, 0, 0])

      lds = LegislatorDistrictScore.find_by!(legislator_term:)
      expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([1, 0, 0, 0])

      lls = LegislatorLocaleScore.find_by!(legislator_term:)
      expect([lls.count_agreed, lls.count_disagreed, lls.count_no_legislator_vote, lls.count_legislator_abstained]).to eql([1, 0, 0, 0])
    end

    it "M-U2: user AGAINST, legislator FOR → disagreed" do
      sway_locale = create(:sway_locale)
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      legislator_term = create(:legislator_term, legislator:, district:)
      user = create(:user)
      user_legislator = create(:user_legislator, user:, legislator:)
      bill = create(:bill, sway_locale:, legislator:)
      create(:legislator_vote, bill:, legislator:, support: LegislatorVote::Support::FOR)
      user_vote = create(:user_vote, user:, bill:, support: LegislatorVote::Support::AGAINST)

      ScoreUpdaterService.new(user_vote).call

      bill_score = BillScore.find_by!(bill:)
      expect(bill_score.for).to eql(0)
      expect(bill_score.against).to eql(1)

      bsd = BillScoreDistrict.find_by!(bill_score:, district:)
      expect(bsd.for).to eql(0)
      expect(bsd.against).to eql(1)

      uls = UserLegislatorTermScore.find_by!(user_legislator:, legislator_term:)
      expect([uls.count_agreed, uls.count_disagreed, uls.count_no_legislator_vote, uls.count_legislator_abstained]).to eql([0, 1, 0, 0])

      lds = LegislatorDistrictScore.find_by!(legislator_term:)
      expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([0, 1, 0, 0])

      lls = LegislatorLocaleScore.find_by!(legislator_term:)
      expect([lls.count_agreed, lls.count_disagreed, lls.count_no_legislator_vote, lls.count_legislator_abstained]).to eql([0, 1, 0, 0])
    end

    it "M-U3: user FOR, legislator has no vote → no_legislator_vote" do
      sway_locale = create(:sway_locale)
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      legislator_term = create(:legislator_term, legislator:, district:)
      user = create(:user)
      user_legislator = create(:user_legislator, user:, legislator:)
      bill = create(:bill, sway_locale:, legislator:)
      user_vote = create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)

      ScoreUpdaterService.new(user_vote).call

      bill_score = BillScore.find_by!(bill:)
      expect(bill_score.for).to eql(1)
      expect(bill_score.against).to eql(0)

      bsd = BillScoreDistrict.find_by!(bill_score:, district:)
      expect(bsd.for).to eql(1)

      uls = UserLegislatorTermScore.find_by!(user_legislator:, legislator_term:)
      expect([uls.count_agreed, uls.count_disagreed, uls.count_no_legislator_vote, uls.count_legislator_abstained]).to eql([0, 0, 1, 0])

      lds = LegislatorDistrictScore.find_by!(legislator_term:)
      expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([0, 0, 1, 0])

      lls = LegislatorLocaleScore.find_by!(legislator_term:)
      expect([lls.count_agreed, lls.count_disagreed, lls.count_no_legislator_vote, lls.count_legislator_abstained]).to eql([0, 0, 1, 0])
    end

    # A legislator's ABSTAIN raises count_legislator_abstained and nothing
    # else; count_disagreed stays 0 — a deliberate change from the old
    # Scoreable#update_agreeable_score, which double-counted it.
    it "M-U4: user FOR, legislator ABSTAIN → legislator_abstained only, disagreed stays 0 (D-WS2-a)" do
      sway_locale = create(:sway_locale)
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      legislator_term = create(:legislator_term, legislator:, district:)
      user = create(:user)
      user_legislator = create(:user_legislator, user:, legislator:)
      bill = create(:bill, sway_locale:, legislator:)
      create(:legislator_vote, bill:, legislator:, support: LegislatorVote::Support::ABSTAIN)
      user_vote = create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)

      ScoreUpdaterService.new(user_vote).call

      uls = UserLegislatorTermScore.find_by!(user_legislator:, legislator_term:)
      expect([uls.count_agreed, uls.count_disagreed, uls.count_no_legislator_vote, uls.count_legislator_abstained]).to eql([0, 0, 0, 1])

      lds = LegislatorDistrictScore.find_by!(legislator_term:)
      expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([0, 0, 0, 1])

      lls = LegislatorLocaleScore.find_by!(legislator_term:)
      expect([lls.count_agreed, lls.count_disagreed, lls.count_no_legislator_vote, lls.count_legislator_abstained]).to eql([0, 0, 0, 1])
    end

    it "M-U5: U1 FOR + U2 AGAINST (both have G; G voted FOR) → split tallies" do
      sway_locale = create(:sway_locale)
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      legislator_term = create(:legislator_term, legislator:, district:)
      user1 = create(:user)
      user2 = create(:user)
      user_legislator1 = create(:user_legislator, user: user1, legislator:)
      user_legislator2 = create(:user_legislator, user: user2, legislator:)
      bill = create(:bill, sway_locale:, legislator:)
      create(:legislator_vote, bill:, legislator:, support: LegislatorVote::Support::FOR)
      user_vote1 = create(:user_vote, user: user1, bill:, support: LegislatorVote::Support::FOR)
      user_vote2 = create(:user_vote, user: user2, bill:, support: LegislatorVote::Support::AGAINST)

      ScoreUpdaterService.new(user_vote1).call
      ScoreUpdaterService.new(user_vote2).call

      bill_score = BillScore.find_by!(bill:)
      expect(bill_score.for).to eql(1)
      expect(bill_score.against).to eql(1)

      bsd = BillScoreDistrict.find_by!(bill_score:, district:)
      expect(bsd.for).to eql(1)
      expect(bsd.against).to eql(1)

      uls1 = UserLegislatorTermScore.find_by!(user_legislator: user_legislator1, legislator_term:)
      expect([uls1.count_agreed, uls1.count_disagreed, uls1.count_no_legislator_vote, uls1.count_legislator_abstained]).to eql([1, 0, 0, 0])

      uls2 = UserLegislatorTermScore.find_by!(user_legislator: user_legislator2, legislator_term:)
      expect([uls2.count_agreed, uls2.count_disagreed, uls2.count_no_legislator_vote, uls2.count_legislator_abstained]).to eql([0, 1, 0, 0])

      lds = LegislatorDistrictScore.find_by!(legislator_term:)
      expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([1, 1, 0, 0])

      lls = LegislatorLocaleScore.find_by!(legislator_term:)
      expect([lls.count_agreed, lls.count_disagreed, lls.count_no_legislator_vote, lls.count_legislator_abstained]).to eql([1, 1, 0, 0])
    end

    # LegislatorLocaleScore covers ALL users in a locale: one vote moves
    # every legislator's score, not just the voter's — G2's must move too,
    # though its DistrictScore must not.
    it "M-U-LLS: a vote moves a non-constituent locale legislator's LLS but not its LDS" do
      sway_locale = create(:sway_locale)
      district1 = create(:district, sway_locale:, name: "district-1")
      district2 = create(:district, sway_locale:, name: "district-2")
      g1 = create(:legislator, district: district1)
      g1_term = create(:legislator_term, legislator: g1, district: district1)
      g2 = create(:legislator, district: district2)
      g2_term = create(:legislator_term, legislator: g2, district: district2)
      user = create(:user)
      create(:user_legislator, user:, legislator: g1) # the user is a constituent of G1 only
      bill = create(:bill, sway_locale:, legislator: g1)
      create(:legislator_vote, bill:, legislator: g1, support: LegislatorVote::Support::FOR)
      create(:legislator_vote, bill:, legislator: g2, support: LegislatorVote::Support::FOR)
      user_vote = create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)

      ScoreUpdaterService.new(user_vote).call

      # G2's locale score counts this user: a voter in the locale who agreed
      # with G2's FOR.
      lls_g2 = LegislatorLocaleScore.find_by!(legislator_term: g2_term)
      expect([lls_g2.count_agreed, lls_g2.count_disagreed, lls_g2.count_no_legislator_vote, lls_g2.count_legislator_abstained]).to eql([1, 0, 0, 0])

      # But a user vote never recomputes G2's DISTRICT score: the user is not
      # G2's constituent, so that path never touches it, and since rows are no
      # longer created automatically, no row exists at all.
      expect(LegislatorDistrictScore.find_by(legislator_term: g2_term)).to be_nil

      # G1 (the voter's own legislator) has both scores populated.
      lls_g1 = LegislatorLocaleScore.find_by!(legislator_term: g1_term)
      expect([lls_g1.count_agreed, lls_g1.count_disagreed, lls_g1.count_no_legislator_vote, lls_g1.count_legislator_abstained]).to eql([1, 0, 0, 0])
      lds_g1 = LegislatorDistrictScore.find_by!(legislator_term: g1_term)
      expect([lds_g1.count_agreed, lds_g1.count_disagreed, lds_g1.count_no_legislator_vote, lds_g1.count_legislator_abstained]).to eql([1, 0, 0, 0])
    end

    # The recompute starts from scratch every time, so running the service again
    # for the same vote — a Solid Queue retry, for example — gives identical
    # rows and counts nothing twice.
    it "M-U9: running the service twice for the same vote is idempotent" do
      sway_locale = create(:sway_locale)
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      legislator_term = create(:legislator_term, legislator:, district:)
      user = create(:user)
      user_legislator = create(:user_legislator, user:, legislator:)
      bill = create(:bill, sway_locale:, legislator:)
      create(:legislator_vote, bill:, legislator:, support: LegislatorVote::Support::FOR)
      user_vote = create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)

      ScoreUpdaterService.new(user_vote).call
      ScoreUpdaterService.new(user_vote).call

      bill_score = BillScore.find_by!(bill:)
      expect(bill_score.for).to eql(1)

      uls = UserLegislatorTermScore.find_by!(user_legislator:, legislator_term:)
      expect([uls.count_agreed, uls.count_disagreed, uls.count_no_legislator_vote, uls.count_legislator_abstained]).to eql([1, 0, 0, 0])

      lds = LegislatorDistrictScore.find_by!(legislator_term:)
      expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([1, 0, 0, 0])
    end

    # The whole recompute runs in ONE transaction; a failure part-way undoes
    # every write. The made-up starting value proves it: without atomic
    # writes, BillScore.for would stay at 1, not revert to 99.
    it "M-U10: a mid-run failure rolls back the whole recompute" do
      sway_locale = create(:sway_locale)
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      create(:legislator_term, legislator:, district:)
      user = create(:user)
      create(:user_legislator, user:, legislator:)
      bill = create(:bill, sway_locale:, legislator:)
      user_vote = create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)

      BillScore.find_by!(bill:).update!({for: 99})

      allow(ScoreRecomputeService).to receive(:recompute_legislator_locale!).and_raise(RuntimeError, "boom")

      expect { ScoreUpdaterService.new(user_vote).call }.to raise_error(RuntimeError, "boom")

      expect(BillScore.find_by!(bill:).for).to eql(99)
    end
  end

  describe "ActionCable broadcast" do
    include_context "Setup"

    it "broadcasts to scores_<user_id> after updating scores" do
      sway_locale, user = setup
      legislator_sway_locale = create(:sway_locale)
      district = create(:district, sway_locale: legislator_sway_locale)
      legislator = create(:legislator, district:)
      create(:legislator_term, legislator:, district:)
      bill = create(:bill, sway_locale: sway_locale, legislator: legislator)
      user_vote = create(:user_vote, user: user, bill: bill)

      expect {
        ScoreUpdaterService.new(user_vote).call
      }.to have_broadcasted_to("scores_#{user.id}")
    end
  end
end
