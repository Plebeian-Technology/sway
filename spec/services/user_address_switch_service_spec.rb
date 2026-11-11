# frozen_string_literal: true

require "rails_helper"

RSpec.describe UserAddressSwitchService do
  describe ".cooldown_active_for?" do
    it "returns true when a UserAddressChange was created within COOLDOWN_PERIOD and false otherwise" do
      user = create(:user)
      addr1 = create(:address, street: "100 E Pratt St")
      addr2 = create(:address, street: "200 E Pratt St")

      expect(described_class.cooldown_active_for?(user)).to be(false)

      old_change = create(
        :user_address_change,
        user: user,
        previous_address: addr1,
        new_address: addr2,
        created_at: 31.days.ago
      )
      expect(old_change.created_at).to be < 30.days.ago
      expect(described_class.cooldown_active_for?(user)).to be(false)

      create(
        :user_address_change,
        user: user,
        previous_address: addr2,
        new_address: addr1,
        created_at: 5.days.ago
      )
      expect(described_class.cooldown_active_for?(user)).to be(true)
    end
  end

  describe "#call" do
    it "reconciles legislators and districts across locales, updates user_address, records UserAddressChange, recomputes scores, and broadcasts refresh" do
      user = create(:user)
      old_locale = create(:sway_locale, :baltimore)
      new_locale = create(:sway_locale, :maryland)

      old_address = create(:address, street: "100 E Pratt St", city: "Baltimore", region_code: "MD", postal_code: "21202")
      new_address = create(:address, street: "1 State Cir", city: "Annapolis", region_code: "MD", postal_code: "21401")
      create(:user_address, user: user, address: old_address)

      old_district = create(:district, sway_locale: old_locale, name: "MD1")
      old_legislator = create(:legislator, district: old_district, sway_locale: old_locale)
      old_seat = Seat.find_or_create_by_identity!(
        district: old_district,
        office_identity: "old-seat-1",
        title: "Representative",
        chamber: "House"
      )
      old_term = create(:legislator_term, legislator: old_legislator, district: old_district, seat: old_seat)
      old_ul = create(:user_legislator, user: user, legislator: old_legislator, active: true)
      old_ud = create(:user_district, user: user, district: old_district, active: true)

      new_district = create(:district, sway_locale: new_locale, name: "MD2")
      new_legislator = create(:legislator, district: new_district, sway_locale: new_locale)
      new_seat = Seat.find_or_create_by_identity!(
        district: new_district,
        office_identity: "new-seat-2",
        title: "Representative",
        chamber: "House"
      )
      new_term = create(:legislator_term, legislator: new_legislator, district: new_district, seat: new_seat)

      bill = create(:bill, sway_locale: old_locale, legislator: old_legislator)
      create(:legislator_vote, bill: bill, legislator: old_legislator, legislator_term: old_term, support: LegislatorVote::Support::FOR)
      create(:user_vote, user: user, bill: bill, support: LegislatorVote::Support::FOR)
      ScoreRecomputeService.recompute_bill!(bill)
      ScoreRecomputeService.recompute_legislator!(old_term)

      bill_score = BillScore.find_by!(bill: bill)
      expect(BillScoreDistrict.find_by(bill_score: bill_score, district: old_district)&.for).to eq(1)
      expect(LegislatorDistrictScore.find_by(legislator_term: old_term)&.count_agreed).to eq(1)

      allow(new_address).to receive(:sway_locales).and_return([new_locale])
      reg_double = instance_double(SwayRegistrationService, district_legislators: [new_legislator])
      allow(SwayRegistrationService).to receive(:new)
        .with(user, new_address, new_locale, invited_by_id: nil, async: false)
        .and_return(reg_double)

      expect {
        described_class.new(user, previous_address: old_address, new_address: new_address).call
      }.to have_broadcasted_to("scores_#{user.id}")

      change = UserAddressChange.find_by!(user: user)

      expect(user.reload.address).to eq(new_address)
      expect(old_ul.reload.active).to be(false)
      expect(old_ud.reload.active).to be(false)

      new_ul = UserLegislator.find_by!(user: user, legislator: new_legislator)
      new_ud = UserDistrict.find_by!(user: user, district: new_district)
      expect(new_ul.active).to be(true)
      expect(new_ud.active).to be(true)

      expect(change.previous_address_id).to eq(old_address.id)
      expect(change.new_address_id).to eq(new_address.id)
      expect(change.deactivated_legislator_ids).to eq([old_legislator.id])
      expect(change.activated_legislator_ids).to eq([new_legislator.id])
      expect(change.deactivated_district_ids).to eq([old_district.id])
      expect(change.activated_district_ids).to eq([new_district.id])
      expect(change.previous_sway_locale_ids).to eq([old_locale.id])
      expect(change.new_sway_locale_ids).to eq([new_locale.id])
      expect(change.prior_vote_count).to eq(1)
      expect(change.prior_voted_bill_ids).to eq([bill.id])
      expect(change.prior_voted_sway_locale_ids).to eq([old_locale.id])

      expect(BillScoreDistrict.find_by(bill_score: bill_score, district: old_district)&.for).to eq(0)
      expect(LegislatorDistrictScore.find_by(legislator_term: old_term)&.count_agreed).to eq(0)
      expect(LegislatorLocaleScore.find_by(legislator_term: old_term)&.count_agreed).to eq(0)
      expect(UserLegislatorTermScore.find_by(user_legislator: new_ul, legislator_term: new_term)).to be_present
    end

    it "re-activates previously deactivated UserLegislator and UserDistrict rows in place without creating duplicates" do
      user = create(:user)
      sway_locale = create(:sway_locale)
      old_address = create(:address, street: "100 E Pratt St")
      new_address = create(:address, street: "200 E Pratt St")
      create(:user_address, user: user, address: old_address)

      district_a = create(:district, sway_locale: sway_locale, name: "MD1")
      legislator_a = create(:legislator, district: district_a, sway_locale: sway_locale)
      create(:legislator_term, legislator: legislator_a, district: district_a)
      district_b = create(:district, sway_locale: sway_locale, name: "MD2")
      legislator_b = create(:legislator, district: district_b, sway_locale: sway_locale)
      create(:legislator_term, legislator: legislator_b, district: district_b)

      create(:user_legislator, user: user, legislator: legislator_a, active: true)
      create(:user_district, user: user, district: district_a, active: true)
      prior_ul_b = create(:user_legislator, user: user, legislator: legislator_b, active: false)
      prior_ud_b = create(:user_district, user: user, district: district_b, active: false)

      allow(new_address).to receive(:sway_locales).and_return([sway_locale])
      reg_double = instance_double(SwayRegistrationService, district_legislators: [legislator_b])
      allow(SwayRegistrationService).to receive(:new)
        .with(user, new_address, sway_locale, invited_by_id: nil, async: false)
        .and_return(reg_double)

      expect {
        described_class.new(user, previous_address: old_address, new_address: new_address).call
      }.to change(UserLegislator, :count).by(0).and change(UserDistrict, :count).by(0)

      expect(prior_ul_b.reload.active).to be(true)
      expect(prior_ud_b.reload.active).to be(true)
    end

    it "returns nil and makes zero database writes when the new address resolves zero legislators" do
      user = create(:user)
      sway_locale = create(:sway_locale)
      old_address = create(:address, street: "100 E Pratt St")
      new_address = create(:address, street: "200 E Pratt St")
      create(:user_address, user: user, address: old_address)

      district = create(:district, sway_locale: sway_locale, name: "MD1")
      legislator = create(:legislator, district: district, sway_locale: sway_locale)
      active_ul = create(:user_legislator, user: user, legislator: legislator, active: true)
      active_ud = create(:user_district, user: user, district: district, active: true)

      allow(new_address).to receive(:sway_locales).and_return([sway_locale])
      reg_double = instance_double(SwayRegistrationService, district_legislators: [])
      allow(SwayRegistrationService).to receive(:new)
        .with(user, new_address, sway_locale, invited_by_id: nil, async: false)
        .and_return(reg_double)

      result = described_class.new(user, previous_address: old_address, new_address: new_address).call

      expect(result).to be_nil
      expect(user.reload.address).to eq(old_address)
      expect(active_ul.reload.active).to be(true)
      expect(active_ud.reload.active).to be(true)
      expect(UserAddressChange.count).to eq(0)
    end

    it "propagates SwayGeocode::ServiceUnavailableError with zero database writes when geocoding fails" do
      user = create(:user)
      sway_locale = create(:sway_locale)
      old_address = create(:address, street: "100 E Pratt St")
      new_address = create(:address, street: "200 E Pratt St")
      create(:user_address, user: user, address: old_address)

      district = create(:district, sway_locale: sway_locale, name: "MD1")
      legislator = create(:legislator, district: district, sway_locale: sway_locale)
      active_ul = create(:user_legislator, user: user, legislator: legislator, active: true)
      active_ud = create(:user_district, user: user, district: district, active: true)

      allow(new_address).to receive(:sway_locales).and_return([sway_locale])
      reg_double = instance_double(SwayRegistrationService)
      allow(reg_double).to receive(:district_legislators).and_raise(SwayGeocode::ServiceUnavailableError, "timeout")
      allow(SwayRegistrationService).to receive(:new)
        .with(user, new_address, sway_locale, invited_by_id: nil, async: false)
        .and_return(reg_double)

      expect {
        described_class.new(user, previous_address: old_address, new_address: new_address).call
      }.to raise_error(SwayGeocode::ServiceUnavailableError)

      expect(user.reload.address).to eq(old_address)
      expect(active_ul.reload.active).to be(true)
      expect(active_ud.reload.active).to be(true)
      expect(UserAddressChange.count).to eq(0)
    end
  end
end
