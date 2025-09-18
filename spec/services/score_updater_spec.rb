# typed: true
# frozen_string_literal: true

RSpec.describe ScoreUpdaterService do
  context "the service is run" do
    describe "#run" do
      it "updates the Scoreable objects associated with the User" do
        address = build(:address)
        sway_locale =
          build(
            :sway_locale,
            city: address.city,
            state: address.region_code,
            country: address.country,
          )
        user = build(:user)
        _user_address = build(:user_address, user:, address:)
        district = build(:district, sway_locale:)
        legislator = create(:legislator, district:)
        bill = create(:bill, legislator:, sway_locale:)

        user_legislator = create(:user_legislator, user:, legislator:)
        _legislator_vote = create(:legislator_vote, bill:, legislator:)

        expect(bill.bill_score).to_not be_nil
        expect(legislator.legislator_district_score).to_not be_nil
        expect(user_legislator.user_legislator_score).to_not be_nil

        expect(BillScore.last&.for).to eql(0)
        expect(BillScoreDistrict.last&.for).to eql(nil)
        expect(UserLegislatorScore.last&.count_agreed).to eql(0)
        expect(LegislatorDistrictScore.last&.count_agreed).to eql(0)

        user_vote = build(:user_vote, user:, bill:)
        expect { ScoreUpdaterService.new(user_vote).run }.to change(
          BillScore,
          :count,
        ).by(0).and change(BillScoreDistrict, :count).by(1).and change(
                      UserLegislatorScore,
                      :count,
                    ).by(0).and change(LegislatorDistrictScore, :count).by(0)

        expect(BillScore.last&.for).to eql(1)
        expect(BillScoreDistrict.last&.for).to eql(1)
        expect(UserLegislatorScore.last&.count_agreed).to eql(1)
        expect(LegislatorDistrictScore.last&.count_agreed).to eql(1)
      end
    end
  end
end
