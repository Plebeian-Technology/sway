require "rails_helper"

RSpec.describe OnLegislatorVoteUpdateScoresJob, type: :job do
    include_context "Setup"

    describe "a legislator's vote is updated in Sway" do
        context "when a user has not yet voted on a bill" do
            context "there is no value for 'no legislator vote' in the BillScore" do
                it "add's the legislator's vote to the BillScore and then changes the LegislatorVote.support" do
                    sway_locale, user = setup

                    legislator = create(:legislator)
                    bill = create(:bill, legislator:, sway_locale:)
                    create(:user_vote, user:, bill:, support: LegislatorVote::Support::FOR)
                    user_legislator = create(:user_legislator, user:, legislator:)
                    legislator_vote = create(:legislator_vote, bill:, legislator:, support: LegislatorVote::Support::FOR)

                    lds = LegislatorDistrictScore.find_by(legislator: legislator_vote.legislator)
                    expect(lds).to_not be_nil

                    uls = UserLegislatorScore.find_by(user_legislator:)
                    expect(uls).to_not be_nil

                    job = OnLegislatorVoteUpdateScoresJob.new
                    job.perform(legislator_vote, nil)

                    lds = LegislatorDistrictScore.find_by(legislator: legislator_vote.legislator)
                    expect(lds.count_agreed).to eql(1)
                    expect(lds.count_disagreed).to eql(0)
                    expect(lds.count_legislator_abstained).to eql(0)
                    expect(lds.count_no_legislator_vote).to eql(0)

                    uls = UserLegislatorScore.find_by(user_legislator:)
                    expect(uls.count_agreed).to eql(1)
                    expect(uls.count_disagreed).to eql(0)
                    expect(uls.count_legislator_abstained).to eql(0)
                    expect(uls.count_no_legislator_vote).to eql(0)

                    # CHANGE SUPPORT

                    legislator_vote.update(support: LegislatorVote::Support::AGAINST)
                    job.perform(legislator_vote, LegislatorVote::Support::FOR)

                    lds = LegislatorDistrictScore.find_by(legislator: legislator_vote.legislator)
                    expect(lds.count_agreed).to eql(0)
                    expect(lds.count_disagreed).to eql(1)
                    expect(lds.count_legislator_abstained).to eql(0)
                    expect(lds.count_no_legislator_vote).to eql(0)

                    uls = UserLegislatorScore.find_by(user_legislator:)
                    expect(uls.count_agreed).to eql(0)
                    expect(uls.count_disagreed).to eql(1)
                    expect(uls.count_legislator_abstained).to eql(0)
                    expect(uls.count_no_legislator_vote).to eql(0)
                end
            end
        end
    end
end
