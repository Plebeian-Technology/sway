# frozen_string_literal: true

require "rails_helper"

RSpec.describe LinkCampaignOrganizationService do
  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:other_locale) { create(:sway_locale, :maryland) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }
  let(:actor) { create(:user, :sway_admin) }
  let(:campaign) { create(:campaign, bill: bill) }
  let(:organization) { create(:organization, sway_locale: sway_locale) }

  def record_decision(decision:, organization_id: nil, organization_name: nil, campaign_record: campaign, bill_record: bill)
    described_class.new(
      bill: bill_record, campaign: campaign_record, actor: actor,
      decision: decision, organization_id: organization_id, organization_name: organization_name
    ).call
  end

  describe "linking an organization" do
    it "returns :linked" do
      expect(record_decision(decision: "linked", organization_id: organization.id)).to eq(:linked)
    end

    it "records both the organization and the decision" do
      record_decision(decision: "linked", organization_id: organization.id)

      expect(campaign.reload.organization_id).to eq(organization.id)
      expect(campaign.organization_link_decision).to eq(Campaign::LINKED)
    end

    it "leaves the campaign's own position untouched" do
      before_state = campaign.slice(:name, :support, :summary, :sender_count, :letter_count)

      record_decision(decision: "linked", organization_id: organization.id)

      expect(campaign.reload.slice(:name, :support, :summary, :sender_count, :letter_count))
        .to eq(before_state)
    end

    it "never creates an Organization row when linking by organization_id" do
      target_id = organization.id

      expect { record_decision(decision: "linked", organization_id: target_id) }
        .not_to change(Organization, :count)
    end

    it "creates a new Organization in the bill's locale and links it when organization_name is provided" do
      expect {
        expect(record_decision(decision: "linked", organization_name: "  Harford Road   Action Coalition  ")).to eq(:linked)
      }.to change(Organization, :count).by(1)

      created = Organization.find_by!(name: "Harford Road Action Coalition", sway_locale: sway_locale)
      expect(campaign.reload.organization_id).to eq(created.id)
      expect(campaign.organization_link_decision).to eq(Campaign::LINKED)
    end

    it "reuses an existing Organization in the bill's locale case-insensitively and creates a new row when the name only exists in another locale" do
      existing = create(:organization, name: "Baltimore Transit Alliance", sway_locale: sway_locale)
      other_locale_org = create(:organization, name: "Maryland Housing Network", sway_locale: other_locale)

      expect {
        expect(record_decision(decision: "linked", organization_name: "baltimore transit alliance")).to eq(:linked)
      }.not_to change(Organization, :count)
      expect(campaign.reload.organization_id).to eq(existing.id)

      expect {
        expect(record_decision(decision: "linked", organization_name: "Maryland Housing Network")).to eq(:linked)
      }.to change(Organization, :count).by(1)
      expect(campaign.reload.organization_id).not_to eq(other_locale_org.id)
      expect(campaign.organization.sway_locale_id).to eq(sway_locale.id)
    end

    it "can be changed to a different organization" do
      record_decision(decision: "linked", organization_id: organization.id)
      second = create(:organization, sway_locale: sway_locale)

      record_decision(decision: "linked", organization_id: second.id)

      expect(campaign.reload.organization_id).to eq(second.id)
    end
  end

  describe "recording that there is no organization" do
    it "returns :recorded_no_organization and clears any earlier link" do
      record_decision(decision: "linked", organization_id: organization.id)

      expect(record_decision(decision: "none")).to eq(:recorded_no_organization)
      expect(campaign.reload.organization_id).to be_nil
      expect(campaign.organization_link_decision).to eq(Campaign::NO_ORGANIZATION)
    end
  end

  describe "recording that it is not determinable yet" do
    it "returns :recorded_undetermined" do
      expect(record_decision(decision: "undetermined")).to eq(:recorded_undetermined)
      expect(campaign.reload.organization_link_decision).to eq(Campaign::UNDETERMINED)
    end

    # The whole point of the separate step: "nobody has looked" and "somebody
    # looked and could not tell" are different answers, and only the second is
    # a decision.
    it "is distinguishable from never having been asked" do
      never_asked = create(:campaign, bill: bill)

      record_decision(decision: "undetermined")

      expect(campaign.reload.organization_link_decision).to eq(Campaign::UNDETERMINED)
      expect(campaign).to be_organization_link_decided
      expect(never_asked.reload.organization_link_decision).to be_nil
      expect(never_asked).not_to be_organization_link_decided
    end
  end

  describe "refusals" do
    it "refuses a campaign that belongs to a different bill" do
      other_bill = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: nil)
      stranger = create(:campaign, bill: other_bill)

      expect(record_decision(decision: "linked", organization_id: organization.id, campaign_record: stranger))
        .to eq(:campaign_not_on_bill)
    end

    it "refuses an unrecognised decision" do
      expect(record_decision(decision: "probably")).to eq(:invalid_decision)
    end

    it "refuses a link with no organization chosen" do
      expect(record_decision(decision: "linked")).to eq(:organization_required)
    end

    it "refuses an organization_name exceeding Campaign::MAX_NAME_CHARS" do
      expect(record_decision(decision: "linked", organization_name: "A" * (Campaign::MAX_NAME_CHARS + 1)))
        .to eq(:organization_name_too_long)
    end

    it "refuses an organization that no longer exists" do
      expect(record_decision(decision: "linked", organization_id: 0)).to eq(:organization_not_found)
    end

    it "refuses an organization from a different locale than the bill" do
      stranger = create(:organization, sway_locale: other_locale)

      expect(record_decision(decision: "linked", organization_id: stranger.id)).to eq(:organization_wrong_locale)
    end

    it "writes nothing when it refuses" do
      record_decision(decision: "probably")

      expect(campaign.reload.organization_link_decision).to be_nil
      expect(campaign.organization_id).to be_nil
    end
  end

  describe "the activity log" do
    it "records the decision against the bill" do
      allow(PipelineActivityLogger).to receive(:log_org_position_decision!)

      record_decision(decision: "linked", organization_id: organization.id)

      expect(PipelineActivityLogger).to have_received(:log_org_position_decision!).with(
        hash_including(bill: bill, decision: :organization_linked, actor: actor)
      )
    end
  end
end
