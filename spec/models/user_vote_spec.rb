# == Schema Information
#
# Table name: user_votes
# Database name: primary
#
#  id         :integer          not null, primary key
#  support    :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  bill_id    :integer          not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_user_votes_on_bill_id              (bill_id)
#  index_user_votes_on_user_id_and_bill_id  (user_id,bill_id) UNIQUE
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#  user_id  (user_id => users.id)
#
require "rails_helper"

RSpec.describe UserVote, type: :model do
  describe "validations" do
    it "is invalid without a support value" do
      vote = build(:user_vote, support: nil)
      expect(vote).not_to be_valid
    end

    it "accepts FOR/AGAINST support values" do
      expect(build(:user_vote)).to be_valid
      expect(build(:user_vote, :against)).to be_valid
    end

    it "does not allow more than one vote per user and bill" do
      existing_vote = create(:user_vote)
      duplicate_vote =
        build(
          :user_vote,
          user: existing_vote.user,
          bill: existing_vote.bill,
          support: LegislatorVote::Support::AGAINST
        )

      expect(duplicate_vote).not_to be_valid
      expect(duplicate_vote.errors[:bill_id]).to include("has already been taken")
    end
  end

  describe "associations" do
    it "belongs to a user" do
      expect(create(:user_vote).user).to be_a(User)
    end

    it "belongs to a bill" do
      expect(create(:user_vote).bill).to be_a(Bill)
    end
  end

  describe "support values" do
    it "accepts FOR / AGAINST / ABSTAIN constants from LegislatorVote::Support" do
      expect(LegislatorVote::Support::FOR).to eq("FOR")
      expect(LegislatorVote::Support::AGAINST).to eq("AGAINST")
      expect(LegislatorVote::Support::ABSTAIN).to eq("ABSTAIN")
    end

    it "upcases support on save" do
      user_vote = create(:user_vote)
      expect(user_vote.support).to eq(LegislatorVote::Support::FOR)
    end
  end

  describe "#for? / #against?" do
    it "returns true for for? when support is FOR" do
      expect(build(:user_vote).for?).to be(true)
    end

    it "returns true for against? when support is AGAINST" do
      expect(build(:user_vote, :against).against?).to be(true)
    end
  end

  # The support value is upcased just before validation runs. So a value set after the
  # object was built — "against" — is already "AGAINST" by the time the allowed-values
  # check looks at it.
  describe "support normalization" do
    it "upcases a lowercase support assigned after instantiation, before validation" do
      user_vote = build(:user_vote)
      user_vote.support = "against"
      expect(user_vote.valid?).to be(true)
      expect(user_vote.support).to eq(LegislatorVote::Support::AGAINST)
    end
  end
end
