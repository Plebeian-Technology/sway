# frozen_string_literal: true

require "rails_helper"

RSpec.describe Campaigns::OrganizationCandidatesService do
  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }
  let(:other_locale) { create(:sway_locale, :maryland) }

  # One draft, two of whose letters sign off as the same organization.
  let(:artifact) do
    {
      "campaign_drafts" => [
        {"id" => "draft-1", "letter_positions" => [0, 1, 2]}
      ],
      "letters" => [
        {"position" => 0, "source_evidence" => {"org_name" => "Baltimore Renters United"}},
        {"position" => 1, "source_evidence" => {"org_name" => "baltimore renters united"}},
        {"position" => 2, "source_evidence" => nil},
        {"position" => 3, "source_evidence" => {"org_name" => "Not In This Draft"}}
      ]
    }
  end

  let(:campaign) do
    create(:campaign, bill: bill, source_campaign_draft_hash: "draft-1")
  end

  before { create(:bill_llm_provisioning, bill: bill, cleaned_testimony: artifact) }

  describe "signature-block evidence" do
    let!(:renters) { create(:organization, name: "Baltimore Renters United", sway_locale: sway_locale) }

    it "proposes an organization this campaign's own letters named" do
      candidate = described_class.call(campaign: campaign).find { |c| c.organization_id == renters.id }

      expect(candidate).not_to be_nil
      expect(candidate.evidence_kind).to eq(described_class::SIGNATURE_BLOCK)
    end

    it "counts the letters that named it, matching case-insensitively" do
      candidate = described_class.call(campaign: campaign).find { |c| c.organization_id == renters.id }

      expect(candidate.letter_count).to eq(2)
    end

    it "reports the name as a letter actually wrote it" do
      candidate = described_class.call(campaign: campaign).find { |c| c.organization_id == renters.id }

      expect(candidate.claimed_name).to eq("Baltimore Renters United")
    end

    it "ignores a letter that belongs to a different draft" do
      create(:organization, name: "Not In This Draft", sway_locale: sway_locale)

      names = described_class.call(campaign: campaign).map(&:organization_name)
      expect(names).not_to include("Not In This Draft")
    end

    it "never proposes an organization from another locale" do
      create(:organization, name: "Baltimore Renters United", sway_locale: other_locale)

      ids = described_class.call(campaign: campaign).map(&:organization_id)
      expect(ids).to contain_exactly(renters.id)
    end

    it "excludes repeat and manually removed letters from letter_count and falls back to extracted_org org_name" do
      coalition = create(:organization, name: "Baltimore Housing Coalition", sway_locale: sway_locale)
      bill.bill_llm_provisioning.update!(
        cleaned_testimony: {
          "campaign_drafts" => [
            {"id" => "draft-1", "letter_positions" => [0, 1, 2, 3]}
          ],
          "letters" => [
            {"position" => 0, "source_evidence" => {"org_name" => "Baltimore Renters United"}},
            {"position" => 1, "repeat" => true, "source_evidence" => {"org_name" => "Baltimore Renters United"}},
            {"position" => 2, "excluded" => true, "source_evidence" => {"org_name" => "Baltimore Renters United"}},
            {"position" => 3, "source_evidence" => nil, "extracted_org" => {"org_name" => "Baltimore Housing Coalition"}}
          ]
        }
      )

      candidates = described_class.call(campaign: campaign)
      renters_candidate = candidates.find { |c| c.organization_id == renters.id }
      coalition_candidate = candidates.find { |c| c.organization_id == coalition.id }

      expect(renters_candidate.letter_count).to eq(1)
      expect(coalition_candidate).not_to be_nil
      expect(coalition_candidate.evidence_kind).to eq(described_class::SIGNATURE_BLOCK)
      expect(coalition_candidate.letter_count).to eq(1)
    end
  end

  describe "bill-position evidence" do
    let!(:incumbent) { create(:organization, name: "Incumbent Group", sway_locale: sway_locale) }

    before { create(:organization_bill_position, bill: bill, organization: incumbent) }

    it "proposes an organization that already holds a position on this bill" do
      candidate = described_class.call(campaign: campaign).find { |c| c.organization_id == incumbent.id }

      expect(candidate.evidence_kind).to eq(described_class::BILL_POSITION)
      expect(candidate.letter_count).to eq(0)
      expect(candidate.claimed_name).to be_nil
    end

    it "excludes an organization whose position on this bill has been deactivated" do
      removed = create(:organization, name: "Removed Group", sway_locale: sway_locale)
      create(:organization_bill_position, bill: bill, organization: removed, active: false)

      ids = described_class.call(campaign: campaign).map(&:organization_id)
      expect(ids).not_to include(removed.id)
    end
  end

  describe "when both kinds of evidence name one organization" do
    let!(:renters) { create(:organization, name: "Baltimore Renters United", sway_locale: sway_locale) }

    before { create(:organization_bill_position, bill: bill, organization: renters) }

    # The letters naming it is the stronger claim, and offering the same
    # organization twice would ask the operator to choose between two rows that
    # mean the same thing.
    it "offers it once, with the signature-block evidence" do
      candidates = described_class.call(campaign: campaign).select { |c| c.organization_id == renters.id }

      expect(candidates.length).to eq(1)
      expect(candidates.first.evidence_kind).to eq(described_class::SIGNATURE_BLOCK)
    end
  end

  describe "ordering" do
    let!(:renters) { create(:organization, name: "Baltimore Renters United", sway_locale: sway_locale) }
    let!(:incumbent) { create(:organization, name: "Incumbent Group", sway_locale: sway_locale) }

    before { create(:organization_bill_position, bill: bill, organization: incumbent) }

    it "puts signature-block evidence ahead of bill-position evidence" do
      expect(described_class.call(campaign: campaign).map(&:organization_id))
        .to eq([renters.id, incumbent.id])
    end
  end

  describe "when there is nothing to read a claim from" do
    it "returns no candidates for a campaign with no source draft" do
      orphan = create(:campaign, bill: bill, source_campaign_draft_hash: nil)

      expect(described_class.call(campaign: orphan)).to be_empty
    end

    it "returns no candidates when the artifact no longer carries that draft" do
      stale = create(:campaign, bill: bill, source_campaign_draft_hash: "draft-gone")

      expect(described_class.call(campaign: stale)).to be_empty
    end

    # The bill-position evidence does not depend on the artifact at all, so it
    # must still stand when the draft is unreadable.
    it "still proposes a bill-position candidate for a campaign with no source draft" do
      incumbent = create(:organization, name: "Incumbent Group", sway_locale: sway_locale)
      create(:organization_bill_position, bill: bill, organization: incumbent)
      orphan = create(:campaign, bill: bill, source_campaign_draft_hash: nil)

      expect(described_class.call(campaign: orphan).map(&:organization_id)).to eq([incumbent.id])
    end
  end
end

# @lat: [[query-plan-indexes#A query-cost guard measures growth, not a ceiling]]
RSpec.describe Campaigns::OrganizationCandidatesService, ".call_all query cost" do
  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  def queries_while
    count = 0
    counter = ->(_name, _start, _finish, _id, payload) {
      count += 1 unless payload[:name].to_s.in?(["SCHEMA", "TRANSACTION"])
    }
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
    count
  end

  it "costs the same for eight campaigns as for one" do
    one = [create(:campaign, bill: bill)]
    eight = one + 7.times.map { create(:campaign, bill: bill) }

    for_one = queries_while { described_class.call_all(bill: bill, campaigns: one) }
    for_eight = queries_while { described_class.call_all(bill: bill, campaigns: eight) }

    expect(for_eight).to eq(for_one)
  end
end
