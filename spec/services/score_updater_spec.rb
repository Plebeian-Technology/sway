# typed: true
# frozen_string_literal: true

RSpec.describe ScoreUpdaterService do
  context 'the service is run' do
    describe '#run' do
      it 'creates new Scoreable objects if none exist' do
        address = create(:address)
        sway_locale = create(:sway_locale, city: address.city, state: address.region_code, country: address.country)
        user = create(:user)
        _user_address = create(:user_address, user:, address:)
        district = create(:district, sway_locale:)
        legislator = create(:legislator, address:, district:)
        _user_legislator = create(:user_legislator, user:, legislator:)
        bill = create(:bill, legislator:, sway_locale:)
        _legislator_vote = create(:legislator_vote, bill:, legislator:)

        user_vote = build(:user_vote, user:, bill:)

        expect do
          ScoreUpdaterService.new(user_vote).run
        end
        .to change(BillScore, :count).by(1)
        .and change(BillScoreDistrict, :count).by(1)
        .and change(UserLegislatorScore, :count).by(1)
        .and change(LegislatorDistrictScore, :count).by(1)

        expect(BillScore.last&.for).to eq 1
        expect(BillScoreDistrict.last&.for).to eq 1
        expect(UserLegislatorScore.last&.count_agreed).to eq 1
        expect(LegislatorDistrictScore.last&.count_agreed).to eq 1
      end
    end
  end
end
