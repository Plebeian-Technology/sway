# typed: true
# frozen_string_literal: true

RSpec.describe InfluenceService do
  describe "#to_builder" do
    it "returns json data describing the sway influence of a user" do
      address = build(:address)
      sway_locale = create(:sway_locale, city: address.city, state: address.region_code, country: address.country)
      user = create(:user)
      _user_address = build(:user_address, user:, address:)
      district = build(:district, sway_locale:)
      legislator = create(:legislator, district:)
      bill = create(:bill, legislator:, sway_locale:)

      create(:user_vote, user:, bill:)
      create(:invite, inviter: user, invitee: create(:user))

      j = InfluenceService.new(user:, sway_locale: address.sway_locales.first).to_builder.attributes!.except("isA?")

      expect(j).to_not be_nil
      expect(j.is_a?(Hash)).to be(true)
      expect(j.fetch("count_invites_redeemed")).to eql(1)
      expect(j.fetch("count_bills_voted_on")).to eql(1)
      expect(j.fetch("total_sway")).to eql(2)
    end
  end
end
