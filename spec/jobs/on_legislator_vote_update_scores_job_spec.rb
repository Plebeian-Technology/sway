require "rails_helper"

# @lat: [[vote-triggered-score-jobs-design#Why OnLegislatorVoteUpdateScoresJob recomputes from scratch instead of applying deltas]]
# Every counts tuple below reads
# (agreed, disagreed, no_legislator_vote, legislator_abstained).
RSpec.describe OnLegislatorVoteUpdateScoresJob, type: :job do
  it "M-L1: G's vote created FOR reclassifies both voters; no_legislator_vote drops to 0" do
    sway_locale = create(:sway_locale)
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)
    legislator_term = create(:legislator_term, legislator:, district:)
    user1 = create(:user)
    user2 = create(:user)
    user_legislator1 = create(:user_legislator, user: user1, legislator:)
    user_legislator2 = create(:user_legislator, user: user2, legislator:)
    bill1 = create(:bill, sway_locale:, legislator:)
    create(:user_vote, user: user1, bill: bill1, support: LegislatorVote::Support::FOR)
    create(:user_vote, user: user2, bill: bill1, support: LegislatorVote::Support::AGAINST)

    # Set up the state the user-vote path would leave behind: the legislator has
    # not voted yet, so both users count as no_legislator_vote.
    ScoreRecomputeService.recompute_user_legislator!(user_legislator1, legislator_term)
    uls1 = UserLegislatorTermScore.find_by!(user_legislator: user_legislator1, legislator_term:)
    expect(uls1.count_no_legislator_vote).to eql(1)

    create(:legislator_vote, bill: bill1, legislator:, support: LegislatorVote::Support::FOR)
    OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id)

    lds = LegislatorDistrictScore.find_by!(legislator_term:)
    expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([1, 1, 0, 0])

    uls1 = UserLegislatorTermScore.find_by!(user_legislator: user_legislator1, legislator_term:)
    expect([uls1.count_agreed, uls1.count_disagreed, uls1.count_no_legislator_vote, uls1.count_legislator_abstained]).to eql([1, 0, 0, 0])

    uls2 = UserLegislatorTermScore.find_by!(user_legislator: user_legislator2, legislator_term:)
    expect([uls2.count_agreed, uls2.count_disagreed, uls2.count_no_legislator_vote, uls2.count_legislator_abstained]).to eql([0, 1, 0, 0])
  end

  # Changing a vote to ABSTAIN counts only as legislator_abstained;
  # count_disagreed stays at 0.
  it "M-L2: G's vote changed FOR→ABSTAIN reclassifies B1 to legislator_abstained only" do
    sway_locale = create(:sway_locale)
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)
    legislator_term = create(:legislator_term, legislator:, district:)
    user1 = create(:user)
    user2 = create(:user)
    create(:user_legislator, user: user1, legislator:)
    create(:user_legislator, user: user2, legislator:)
    bill1 = create(:bill, sway_locale:, legislator:)
    create(:user_vote, user: user1, bill: bill1, support: LegislatorVote::Support::FOR)
    create(:user_vote, user: user2, bill: bill1, support: LegislatorVote::Support::AGAINST)
    legislator_vote = create(:legislator_vote, bill: bill1, legislator:, support: LegislatorVote::Support::FOR)
    OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id)

    legislator_vote.update!(support: LegislatorVote::Support::ABSTAIN)
    OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id)

    lds = LegislatorDistrictScore.find_by!(legislator_term:)
    expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([0, 0, 0, 2])
  end

  # The old job overwrote the running totals with the counts from a single bill,
  # so the second bill's vote wiped out the first bill's contribution. Rebuilding
  # everything from the source data keeps it.
  it "M-L3: a second bill's legislator vote does not erase the first (cumulative)" do
    sway_locale = create(:sway_locale)
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)
    legislator_term = create(:legislator_term, legislator:, district:)
    user1 = create(:user)
    user2 = create(:user)
    create(:user_legislator, user: user1, legislator:)
    create(:user_legislator, user: user2, legislator:)
    bill1 = create(:bill, sway_locale:, legislator:, scheduled_release_date_utc: 1.day.ago)
    create(:user_vote, user: user1, bill: bill1, support: LegislatorVote::Support::FOR)
    create(:user_vote, user: user2, bill: bill1, support: LegislatorVote::Support::AGAINST)
    create(:legislator_vote, bill: bill1, legislator:, support: LegislatorVote::Support::FOR)
    OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id)

    bill2 = create(:bill, sway_locale:, legislator:, scheduled_release_date_utc: 2.days.ago)
    create(:user_vote, user: user1, bill: bill2, support: LegislatorVote::Support::FOR)
    create(:legislator_vote, bill: bill2, legislator:, support: LegislatorVote::Support::FOR)
    OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id)

    lds = LegislatorDistrictScore.find_by!(legislator_term:)
    expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([2, 1, 0, 0])
  end

  # Destroying the vote puts that bill back to no_legislator_vote in every total.
  it "M-L4: destroying G's vote reverts the bill to no_legislator_vote" do
    sway_locale = create(:sway_locale)
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)
    legislator_term = create(:legislator_term, legislator:, district:)
    user1 = create(:user)
    user2 = create(:user)
    create(:user_legislator, user: user1, legislator:)
    create(:user_legislator, user: user2, legislator:)
    bill1 = create(:bill, sway_locale:, legislator:)
    create(:user_vote, user: user1, bill: bill1, support: LegislatorVote::Support::FOR)
    create(:user_vote, user: user2, bill: bill1, support: LegislatorVote::Support::AGAINST)
    legislator_vote = create(:legislator_vote, bill: bill1, legislator:, support: LegislatorVote::Support::FOR)
    OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id)

    legislator_vote.destroy!
    OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id)

    lds = LegislatorDistrictScore.find_by!(legislator_term:)
    expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([0, 0, 2, 0])
  end

  # Because every total is rebuilt from scratch, running the job twice leaves
  # identical rows.
  it "M-L6: performing the job twice is idempotent" do
    sway_locale = create(:sway_locale)
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)
    legislator_term = create(:legislator_term, legislator:, district:)
    user1 = create(:user)
    create(:user_legislator, user: user1, legislator:)
    bill1 = create(:bill, sway_locale:, legislator:)
    create(:user_vote, user: user1, bill: bill1, support: LegislatorVote::Support::FOR)
    create(:legislator_vote, bill: bill1, legislator:, support: LegislatorVote::Support::FOR)

    OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id)
    OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id)

    lds = LegislatorDistrictScore.find_by!(legislator_term:)
    expect([lds.count_agreed, lds.count_disagreed, lds.count_no_legislator_vote, lds.count_legislator_abstained]).to eql([1, 0, 0, 0])
  end

  # The legislator has already been destroyed, through a dependent: :destroy
  # cascade, by the time the job runs. It should do nothing and raise nothing.
  it "M-L7: a missing legislator is a no-op" do
    expect {
      OnLegislatorVoteUpdateScoresJob.new.perform(999_999)
    }.not_to raise_error
  end

  # A legislator with no current legislator_term — an executive, for example,
  # who is out of scope for term scoring — means there is nothing to do. The job
  # must not raise AssociationTypeMismatch or ArgumentError trying to recompute
  # against a nil term.
  it "a legislator with no current term is a no-op" do
    sway_locale = create(:sway_locale)
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)

    expect {
      OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id)
    }.not_to raise_error
    # The score table is now keyed on legislator_term alone, so find the person
    # by joining through the term. find_by(legislator:) would aim at the
    # legislator_id column, which has been dropped.
    expect(
      LegislatorDistrictScore.joins(:legislator_term).where(legislator_terms: {legislator_id: legislator.id})
    ).not_to exist
  end

  it "recomputes historical legislator_term and includes inactive UserLegislator rows when legislator_term_id is for a prior term" do
    sway_locale = create(:sway_locale, :congress)
    district = create(:district, sway_locale:)
    legislator = create(:legislator, district:)
    prior_term = create(:legislator_term, :prior_term, legislator:, district:)
    _current_term = create(:legislator_term, legislator:, district:)
    user = create(:user)
    inactive_ul = create(:user_legislator, user:, legislator:, active: false)
    session_prior = create(:legislative_session, :prior, sway_locale:)
    prior_bill = create(
      :bill,
      sway_locale:,
      legislator:,
      legislative_session: session_prior,
      introduced_date_time_utc: Time.zone.local(2024, 5, 1),
      scheduled_release_date_utc: Date.new(2024, 5, 1)
    )
    create(:user_vote, user:, bill: prior_bill, support: LegislatorVote::Support::FOR)
    create(:legislator_vote, bill: prior_bill, legislator:, legislator_term: prior_term, support: LegislatorVote::Support::FOR)

    OnLegislatorVoteUpdateScoresJob.new.perform(legislator.id, prior_term.id)

    ults = UserLegislatorTermScore.find_by!(user_legislator: inactive_ul, legislator_term: prior_term)
    expect(ults.count_agreed).to eq(1)
  end
end
