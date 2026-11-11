# frozen_string_literal: true

RSpec.describe InfluenceService do
  describe "#to_builder" do
    it "returns json data describing the sway influence of a user" do
      address = build(:address)
      sway_locale =
        create(
          :sway_locale,
          city: address.city,
          state: address.region_code,
          country: address.country
        )
      user = create(:user)
      _user_address = build(:user_address, user:, address:)
      district = create(:district, sway_locale:)
      legislator = create(:legislator, district:)
      bill = create(:bill, legislator:, sway_locale:)

      create(:user_vote, user:, bill:)
      create(:invite, inviter: user, invitee: create(:user))

      j =
        InfluenceService
          .new(user:, sway_locale: address.sway_locales.first)
          .to_builder
          .attributes!
          .except("isA?")

      expect(j).to_not be_nil
      expect(j.is_a?(Hash)).to be(true)
      expect(j.fetch("count_invites_redeemed")).to eql(1)
      expect(j.fetch("count_bills_voted_on")).to eql(1)
      expect(j.fetch("count_bills_shared")).to eql(0)
      expect(j.fetch("total_sway")).to eql(2)
    end

    context "with bill shares" do
      let(:address) { build(:address) }
      let!(:sway_locale) do
        create(
          :sway_locale,
          city: address.city,
          state: address.region_code,
          country: address.country
        )
      end
      let(:user) { create(:user) }
      let!(:user_address) { create(:user_address, user:, address:) }
      let(:district) { create(:district, sway_locale:) }
      let(:legislator) { create(:legislator, district:) }
      let(:bill) { create(:bill, legislator:, sway_locale:) }

      before do
        create(:user_vote, user:, bill:)
        create(:invite, inviter: user, invitee: create(:user))
      end

      it "increments count_bills_shared and total_sway for a redeemed share on a bill in the active locale" do
        create(:user_bill_share, :redeemed, user:, bill:)

        j =
          InfluenceService
            .new(user:, sway_locale:)
            .to_builder
            .attributes!
            .except("isA?")

        expect(j.fetch("count_invites_redeemed")).to eql(1)
        expect(j.fetch("count_bills_voted_on")).to eql(1)
        expect(j.fetch("count_bills_shared")).to eql(1)
        expect(j.fetch("total_sway")).to eql(3)
      end

      it "increments count_bills_shared and total_sway for multiple redeemed shares on distinct bills in the active locale" do
        second_bill = create(:bill, legislator:, sway_locale:)
        create(:user_bill_share, :redeemed, user:, bill:)
        create(:user_bill_share, :redeemed, user:, bill: second_bill)

        j =
          InfluenceService
            .new(user:, sway_locale:)
            .to_builder
            .attributes!
            .except("isA?")

        expect(j.fetch("count_invites_redeemed")).to eql(1)
        expect(j.fetch("count_bills_voted_on")).to eql(1)
        expect(j.fetch("count_bills_shared")).to eql(2)
        expect(j.fetch("total_sway")).to eql(4)
      end

      it "does not count an unredeemed bill share in count_bills_shared or total_sway" do
        create(:user_bill_share, user:, bill:, redeemed_at: nil)

        j =
          InfluenceService
            .new(user:, sway_locale:)
            .to_builder
            .attributes!
            .except("isA?")

        expect(j.fetch("count_bills_shared")).to eql(0)
        expect(j.fetch("total_sway")).to eql(2)
      end

      it "does not count a redeemed bill share on a bill in a different locale" do
        other_locale = create(:sway_locale, city: "Annapolis", state: "MD", country: "USA")
        other_bill = create(:bill, sway_locale: other_locale)
        create(:user_bill_share, :redeemed, user:, bill: other_bill)

        j =
          InfluenceService
            .new(user:, sway_locale:)
            .to_builder
            .attributes!
            .except("isA?")

        expect(j.fetch("count_bills_shared")).to eql(0)
        expect(j.fetch("total_sway")).to eql(2)
      end

      it "does not count a redeemed bill share created by a different user on the same bill" do
        other_user = create(:user)
        create(:user_bill_share, :redeemed, user: other_user, bill:)

        j =
          InfluenceService
            .new(user:, sway_locale:)
            .to_builder
            .attributes!
            .except("isA?")

        expect(j.fetch("count_bills_shared")).to eql(0)
        expect(j.fetch("total_sway")).to eql(2)
      end
    end
  end
end
