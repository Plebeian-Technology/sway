# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeedItemResource, type: :model do
  describe "#serializable_hash" do
    it "serializes user_joined items" do
      occurred_at = Time.utc(2026, 11, 1, 12, 0, 0)
      item = FeedQuery::Item.new(
        kind: "user_joined",
        key: "user_joined:42",
        occurred_at:
      )

      hash = described_class.new(item).serializable_hash.transform_keys(&:to_s)

      expect(hash).to eq(
        "key" => "user_joined:42",
        "kind" => "user_joined",
        "occurred_at" => occurred_at.iso8601,
        "sway_locale" => nil,
        "bill" => nil,
        "legislator" => nil,
        "legislators" => [],
        "organization" => nil,
        "user_support" => nil,
        "legislator_support" => nil,
        "agreement" => nil
      )
    end

    it "serializes representatives_found items with legislator summaries" do
      sway_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
      district = create(:district, sway_locale:, name: "MD1")
      legislator = create(
        :legislator,
        first_name: "Ada",
        last_name: "Lovelace",
        photo_url: "https://example.test/ada.jpg"
      )
      create(:legislator_term, legislator:, district:, title: "Councilmember")
      occurred_at = Time.utc(2026, 11, 2, 10, 0, 0)
      item = FeedQuery::Item.new(
        kind: "representatives_found",
        key: "representatives_found:7",
        occurred_at:,
        legislators: [legislator]
      )

      hash = described_class.new(item).serializable_hash.transform_keys(&:to_s)

      expect(hash["kind"]).to eq("representatives_found")
      expect(hash["legislator"]).to be_nil
      expect(hash["legislators"]).to eq([
        {
          id: legislator.id,
          full_name: "Ada Lovelace",
          title: "Councilmember",
          district_name: "MD1",
          photo_url: "https://example.test/ada.jpg"
        }
      ])
    end

    it "serializes legislative_term_began items with short locale names" do
      city_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
      state_locale = create(:sway_locale, city: "maryland", state: "maryland", country: "united_states")
      congress_locale = create(:sway_locale, city: "congress", state: "congress", country: "united_states")
      occurred_at = Time.utc(2026, 1, 14, 0, 0, 0)

      city_hash = described_class.new(
        FeedQuery::Item.new(kind: "legislative_term_began", key: "legislative_term_began:1", occurred_at:, sway_locale: city_locale)
      ).serializable_hash.transform_keys(&:to_s)
      state_hash = described_class.new(
        FeedQuery::Item.new(kind: "legislative_term_began", key: "legislative_term_began:2", occurred_at:, sway_locale: state_locale)
      ).serializable_hash.transform_keys(&:to_s)
      congress_hash = described_class.new(
        FeedQuery::Item.new(kind: "legislative_term_began", key: "legislative_term_began:3", occurred_at:, sway_locale: congress_locale)
      ).serializable_hash.transform_keys(&:to_s)

      expect(city_hash["sway_locale"]).to eq(id: city_locale.id, name: "Baltimore")
      expect(state_hash["sway_locale"]).to eq(id: state_locale.id, name: "Maryland")
      expect(congress_hash["sway_locale"]).to eq(id: congress_locale.id, name: "U.S. Congress")
    end

    it "serializes bill_of_the_month_released items with bill summary and user_support" do
      sway_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
      bill = create(:bill, sway_locale:, external_id: "25-0010", title: "Transit Bill", summary: "Expands bus service.")
      user = create(:user)
      user_vote = create(:user_vote, user:, bill:, support: "FOR")
      occurred_at = Time.utc(2026, 11, 1, 0, 0, 0)

      item = FeedQuery::Item.new(
        kind: "bill_of_the_month_released",
        key: "bill_of_the_month_released:#{bill.id}",
        occurred_at:,
        sway_locale:,
        bill:,
        user_vote:
      )

      hash = described_class.new(item).serializable_hash.transform_keys(&:to_s)

      expect(hash["bill"]).to eq(
        id: bill.id,
        external_id: "25-0010",
        title: "Transit Bill",
        summary: "Expands bus service."
      )
      expect(hash["user_support"]).to eq("FOR")
      expect(hash["legislator_support"]).to be_nil
      expect(hash["agreement"]).to be_nil
    end

    it "serializes legislator_voted items and computes agreement" do
      sway_locale = create(:sway_locale, city: "maryland", state: "maryland", country: "united_states")
      district = create(:district, sway_locale:, name: "MD40")
      legislator = create(:legislator, first_name: "Grace", last_name: "Hopper")
      (legislator.active_term || create(:legislator_term, legislator:, district:)).update!(
        district:,
        title: "Delegate"
      )
      legislator.reload
      bill = create(:bill, sway_locale:, legislator:, external_id: "HB-100", title: "Clean Air Act", summary: "Reduces emissions.")
      user = create(:user)
      occurred_at = Time.utc(2026, 3, 15, 16, 0, 0)

      agree_hash = described_class.new(
        FeedQuery::Item.new(
          kind: "legislator_voted",
          key: "legislator_voted:1",
          occurred_at:,
          sway_locale:,
          bill:,
          legislator:,
          legislator_vote: build(:legislator_vote, bill:, legislator:, support: "FOR"),
          user_vote: build(:user_vote, user:, bill:, support: "FOR")
        )
      ).serializable_hash.transform_keys(&:to_s)

      differ_hash = described_class.new(
        FeedQuery::Item.new(
          kind: "legislator_voted",
          key: "legislator_voted:2",
          occurred_at:,
          sway_locale:,
          bill:,
          legislator:,
          legislator_vote: build(:legislator_vote, bill:, legislator:, support: "AGAINST"),
          user_vote: build(:user_vote, user:, bill:, support: "FOR")
        )
      ).serializable_hash.transform_keys(&:to_s)

      unvoted_hash = described_class.new(
        FeedQuery::Item.new(
          kind: "legislator_voted",
          key: "legislator_voted:3",
          occurred_at:,
          sway_locale:,
          bill:,
          legislator:,
          legislator_vote: build(:legislator_vote, bill:, legislator:, support: "FOR"),
          user_vote: nil
        )
      ).serializable_hash.transform_keys(&:to_s)

      abstain_hash = described_class.new(
        FeedQuery::Item.new(
          kind: "legislator_voted",
          key: "legislator_voted:4",
          occurred_at:,
          sway_locale:,
          bill:,
          legislator:,
          legislator_vote: build(:legislator_vote, bill:, legislator:, support: "ABSTAIN"),
          user_vote: build(:user_vote, user:, bill:, support: "FOR")
        )
      ).serializable_hash.transform_keys(&:to_s)

      expect(agree_hash["agreement"]).to eq("agree")
      expect(agree_hash["user_support"]).to eq("FOR")
      expect(agree_hash["legislator_support"]).to eq("FOR")
      expect(agree_hash["legislator"]).to eq(
        id: legislator.id,
        full_name: "Grace Hopper",
        title: "Delegate",
        district_name: "MD40",
        photo_url: legislator.photo_url
      )

      expect(differ_hash["agreement"]).to eq("differ")
      expect(unvoted_hash["agreement"]).to be_nil
      expect(abstain_hash["agreement"]).to be_nil
    end

    it "serializes organization_position_taken items with formatted support" do
      sway_locale = create(:sway_locale, city: "baltimore", state: "maryland", country: "united_states")
      organization = create(:organization, sway_locale:, name: "Transit Riders United")
      bill = create(:bill, sway_locale:, external_id: "25-0020", title: "Bus Lane Act", summary: "Dedicated bus lanes.")
      occurred_at = Time.utc(2026, 4, 2, 15, 0, 0)

      for_pos = create(:organization_bill_position, organization:, bill:, support: "FOR", active: true)
      against_pos = build(:organization_bill_position, organization:, bill:, support: "AGAINST", active: true)
      abstain_pos = build(:organization_bill_position, organization:, bill:, support: "ABSTAIN", active: true)

      for_hash = described_class.new(
        FeedQuery::Item.new(
          kind: "organization_position_taken",
          key: "organization_position_taken:#{for_pos.id}",
          occurred_at:,
          sway_locale:,
          bill:,
          organization_bill_position: for_pos
        )
      ).serializable_hash.transform_keys(&:to_s)
      against_hash = described_class.new(
        FeedQuery::Item.new(
          kind: "organization_position_taken",
          key: "organization_position_taken:2",
          occurred_at:,
          sway_locale:,
          bill:,
          organization_bill_position: against_pos
        )
      ).serializable_hash.transform_keys(&:to_s)
      abstain_hash = described_class.new(
        FeedQuery::Item.new(
          kind: "organization_position_taken",
          key: "organization_position_taken:3",
          occurred_at:,
          sway_locale:,
          bill:,
          organization_bill_position: abstain_pos
        )
      ).serializable_hash.transform_keys(&:to_s)

      expect(for_hash["organization"]).to eq(id: organization.id, name: "Transit Riders United", support: "Support")
      expect(against_hash["organization"]).to eq(id: organization.id, name: "Transit Riders United", support: "Oppose")
      expect(abstain_hash["organization"]).to eq(id: organization.id, name: "Transit Riders United", support: "Neutral")
    end
  end
end
