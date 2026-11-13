# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeedBroadcaster, type: :service do
  describe ".notify" do
    it "broadcasts feed_updated to each given user id's stream" do
      expect { described_class.notify([11, 12]) }
        .to have_broadcasted_to("feed_11").with(type: "feed_updated")
        .and have_broadcasted_to("feed_12").with(type: "feed_updated")
    end

    it "broadcasts nothing when given an empty collection" do
      allow(ActionCable.server).to receive(:broadcast)

      described_class.notify([])

      expect(ActionCable.server).not_to have_received(:broadcast)
    end
  end

  describe ".users_for_locale" do
    it "returns distinct users with an active user_legislator in that locale" do
      target_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
      other_locale = create(:sway_locale, city: "maryland", state: "maryland", country: "united_states")

      target_district = create(:district, sway_locale: target_locale)
      other_district = create(:district, sway_locale: other_locale)

      leg_1 = create(:legislator, district: target_district)
      leg_2 = create(:legislator, district: target_district)
      other_leg = create(:legislator, district: other_district)

      active_user = create(:user)
      create(:user_legislator, user: active_user, legislator: leg_1, active: true)
      create(:user_legislator, user: active_user, legislator: leg_2, active: true)

      inactive_user = create(:user)
      create(:user_legislator, user: inactive_user, legislator: leg_1, active: false)

      other_locale_user = create(:user)
      create(:user_legislator, user: other_locale_user, legislator: other_leg, active: true)

      expect(described_class.users_for_locale(target_locale).to_a).to eq([active_user])
    end
  end
end
