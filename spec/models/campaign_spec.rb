# frozen_string_literal: true

require "rails_helper"

# A campaign is advocacy about ONE bill — the organization is
# the thing that spans bills. This replaces the earlier locale-wide model,
# where a Campaign matched a CampaignBillPosition per bill.
# == Schema Information
#
# Table name: campaigns
# Database name: primary
#
#  id                         :integer          not null, primary key
#  active                     :boolean          default(FALSE), not null
#  ai_summary                 :text
#  icon_url                   :string
#  letter_count               :integer
#  name                       :string
#  organization_link_decision :string
#  sender_count               :integer
#  source_campaign_draft_hash :string
#  summary                    :text             not null
#  support                    :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  bill_id                    :integer          not null
#  organization_id            :integer
#
# Indexes
#
#  index_campaigns_on_bill_and_name               (bill_id,name) UNIQUE WHERE name IS NOT NULL
#  index_campaigns_on_bill_id                     (bill_id)
#  index_campaigns_on_organization_id             (organization_id)
#  index_campaigns_on_organization_link_decision  (organization_link_decision)
#
# Foreign Keys
#
#  bill_id          (bill_id => bills.id)
#  organization_id  (organization_id => organizations.id)
#
RSpec.describe Campaign, type: :model do
  describe "associations" do
    it "belongs to a bill" do
      record = create(:campaign)
      expect(record.bill).to be_a(Bill)
    end

    it "has a sway_locale through its bill" do
      record = create(:campaign)
      expect(record.sway_locale).to eq(record.bill.sway_locale)
    end

    # @lat: [[campaign-approval#An organization link carries the decision that made it]]
    it "may belong to an organization" do
      org = create(:organization)
      record = create(:campaign, organization: org, organization_link_decision: Campaign::LINKED)
      expect(record.organization).to eq(org)
    end

    it "may reference no organization at all" do
      record = create(:campaign, organization: nil)
      expect(record.organization).to be_nil
    end
  end

  describe "validations" do
    it "saves with a name and a bill" do
      expect(create(:campaign)).to be_valid
    end

    it "saves with no name and a bill" do
      expect(create(:campaign, :unnamed)).to be_valid
    end

    it "lets two unnamed campaigns exist on the same bill" do
      bill = create(:bill)
      first = create(:campaign, :unnamed, bill: bill)
      second = create(:campaign, :unnamed, bill: bill)
      expect(first).to be_persisted
      expect(second).to be_persisted
    end

    it "refuses two campaigns with the same name on the same bill" do
      bill = create(:bill)
      create(:campaign, name: "Save The Park", bill: bill)
      dup = build(:campaign, name: "Save The Park", bill: bill)
      expect(dup.valid?).to be(false)
      expect(dup.errors[:name]).to be_present
    end

    # @lat: [[campaign-approval#A campaign belongs to one bill]]
    it "lets two campaigns share a name across different bills" do
      first_bill = create(:bill)
      second_bill = create(:bill)
      first = create(:campaign, name: "Save The Park", bill: first_bill)
      second = create(:campaign, name: "Save The Park", bill: second_bill)
      expect(first).to be_persisted
      expect(second).to be_persisted
    end

    it "refuses a name longer than MAX_NAME_CHARS" do
      campaign = build(:campaign, name: "a" * (Campaign::MAX_NAME_CHARS + 1))
      expect(campaign.valid?).to be(false)
      expect(campaign.errors[:name]).to be_present
    end

    it "allows a name exactly MAX_NAME_CHARS long" do
      campaign = build(:campaign, name: "a" * Campaign::MAX_NAME_CHARS)
      expect(campaign.valid?).to be(true)
    end

    it "refuses a blank support" do
      campaign = build(:campaign, support: "")
      expect(campaign.valid?).to be(false)
      expect(campaign.errors[:support]).to be_present
    end

    it "refuses a blank summary" do
      campaign = build(:campaign, summary: "")
      expect(campaign.valid?).to be(false)
      expect(campaign.errors[:summary]).to be_present
    end
  end

  # Moved here from the deleted CampaignBillPosition model.
  # Mapping the wire-side stance values to the legacy support-column enum
  # values lives in one place, mirroring OrganizationBillPosition's own copy.
  describe ".normalize_support" do
    it "maps 'support' to 'FOR'" do
      expect(described_class.normalize_support("support")).to eq("FOR")
    end

    it "maps 'oppose' to 'AGAINST'" do
      expect(described_class.normalize_support("oppose")).to eq("AGAINST")
    end

    it "maps 'neutral' to 'ABSTAIN'" do
      expect(described_class.normalize_support("neutral")).to eq("ABSTAIN")
    end

    it "passes legacy 'FOR'/'AGAINST'/'ABSTAIN' values through unchanged" do
      %w[FOR AGAINST ABSTAIN].each do |v|
        expect(described_class.normalize_support(v)).to eq(v)
      end
    end

    it "returns nil for unrecognised inputs" do
      expect(described_class.normalize_support("garbage")).to be_nil
      expect(described_class.normalize_support(nil)).to be_nil
      expect(described_class.normalize_support("")).to be_nil
    end
  end

  # A campaign can never be followed. There is no campaign_follows table and
  # no follow path — this is an absence, not a behavior, so it is not proved here.

  # The two columns have to agree: a row saying "linked" with no
  # organization, or an organization under any other decision, is a record
  # nobody can read.
  describe "the organization link invariant" do
    let(:campaign) { create(:campaign) }
    let(:organization) { create(:organization, sway_locale: campaign.bill.sway_locale) }

    it "refuses linked with no organization" do
      campaign.organization_link_decision = Campaign::LINKED

      expect(campaign).not_to be_valid
    end

    it "refuses an organization under a decision other than linked" do
      campaign.organization = organization
      campaign.organization_link_decision = Campaign::NO_ORGANIZATION

      expect(campaign).not_to be_valid
    end

    it "accepts linked with an organization" do
      campaign.organization = organization
      campaign.organization_link_decision = Campaign::LINKED

      expect(campaign).to be_valid
    end

    it "accepts no decision at all, which means nobody has been asked" do
      expect(campaign.organization_link_decision).to be_nil
      expect(campaign).to be_valid
      expect(campaign).not_to be_organization_link_decided
    end

    it "refuses a decision value it does not recognise" do
      campaign.organization_link_decision = "probably"

      expect(campaign).not_to be_valid
    end
  end
end
