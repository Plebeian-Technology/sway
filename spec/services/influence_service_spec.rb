# typed: true
# frozen_string_literal: true

RSpec.describe InfluenceService do
  describe '#to_builder' do
    it 'returns json data describing the sway influence of a user' do
      address = build(:address)
      sway_locale = build(:sway_locale, city: address.city, state: address.region_code, country: address.country)
      user = build(:user)
      _user_address = build(:user_address, user:, address:)
      district = build(:district, sway_locale:)
      legislator = build(:legislator, address:, district:)
      bill = build(:bill, legislator:, sway_locale:)

      create(:user_vote, user:, bill:)
      create(:invite, inviter: user, invitee: create(:user))

      j = InfluenceService.new(user:, sway_locale: address.sway_locales.first).to_builder.attributes!

      expect(j).to_not be_nil
      expect(j.is_a?(Hash)).to be(true)
      expect(j.fetch('countInvitesRedeemed')).to eql(1)
      expect(j.fetch('countBillsVotedOn')).to eql(1)
      expect(j.fetch('totalSway')).to eql(2)
    end
  end
end
