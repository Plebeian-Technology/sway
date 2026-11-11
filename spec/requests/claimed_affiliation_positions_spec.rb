# frozen_string_literal: true

require "rails_helper"

# BillCreatorClaimedAffiliationCard approves through
# BillsController#approve_org_position, the SAME endpoint the ordinary draft
# card uses, sending no draft :index — a claimed affiliation is not an entry
# in draft_org_positions, so there is nothing at an index to promote.
#
# That made it indistinguishable from the OTHER caller with no :index: an
# admin asserting a position from their own knowledge, which the evidence
# rules correctly do not apply to. ApproveOrgPositionService decided which
# was which by the ABSENCE of a parameter, so every bill-level guard skipped
# for a card whose whole content is drawn from this bill's testimony — while
# the card itself greyed its own Approve button on two of those same rules.
#
# The card now names what it is acting on (the letter's position in the
# cleaned artifact, already served to it as a stable identity), so the three
# caller classes are told apart by what they say rather than by what they
# omit.
RSpec.describe "POST /bills/:id/approve_org_position (claimed affiliation)", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:admin) { create(:user, :sway_admin) }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  before { session_hash[:user_id] = admin.id }

  # Bodies are padded to exactly the length each entry claims and joined, so
  # an offset can never point past the end of "text". A fixture that claims
  # more characters than it holds reports its own letters as never reaching
  # the model, which manufactures a coverage gap and proves nothing.
  def claimed_affiliation_artifact(specs)
    offset = 0
    letters = specs.each_with_index.map do |spec, position|
      entry = {
        "position" => position,
        "character_offset" => offset,
        "characters" => spec[:chars],
        "sender_address" => spec[:sender],
        "sender_domain" => "example.com",
        "source_kind" => spec[:kind],
        "source_evidence" => spec[:evidence]
      }
      offset += spec[:chars]
      entry
    end
    text = specs.map { |spec| spec[:body].ljust(spec[:chars], " ")[0, spec[:chars]] }.join

    {
      "version" => 1,
      "text" => text,
      "counts" => {"raw_chars" => text.length, "cleaned_chars" => text.length},
      "letters" => letters,
      "campaign_drafts" => []
    }
  end

  def claimed_affiliation_letter(chars:, body: "I write on behalf of the Waverly Tenants Alliance.")
    {
      chars: chars, body: "From: dana@example.com\n#{body}\n", sender: "dana@example.com",
      kind: "person_speaking_for_org",
      evidence: {"phrase" => "Waverly Tenants Alliance", "role" => "Executive Director", "sender" => "dana@example.com"}
    }
  end

  def resident_letter(chars:, body:)
    {chars: chars, body: body, sender: "resident@example.com", kind: "person_speaking_for_self", evidence: nil}
  end

  describe "when testimony was left out and nobody acknowledged it" do
    let!(:provisioning) do
      create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: "R" * 200_000,
        cleaned_testimony: claimed_affiliation_artifact([
          claimed_affiliation_letter(chars: 160_000),
          resident_letter(chars: 40_000, body: "From: resident@example.com\nI support this bill.\n")
        ]),
        cleaned_testimony_at: 1.hour.ago
      )
    end

    it "refuses the approval and publishes nothing" do
      expect {
        post approve_org_position_bill_path(bill),
          params: {
            org_name: "Waverly Tenants Alliance",
            support: "support",
            summary: "Backs the bill on behalf of its members.",
            claimed_affiliation_position: 0
          }
      }.not_to change { [Organization.count, OrganizationBillPosition.count] }

      # A refusal has to SAY it refused. Both of this phase's own guards fell
      # into the controller's final else and flashed "Approved ..." while the
      # service had written nothing.
      expect(flash[:notice]).to be_nil
    end
  end

  describe "when the name is a person this bill's testimony read as speaking for themselves" do
    # The kind-of-source backstop, and this is the card it was written for: the operator
    # types the organization name by hand, pre-filled with raw text lifted
    # out of somebody's letter.
    let!(:provisioning) do
      create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: "R" * 900,
        cleaned_testimony: claimed_affiliation_artifact([
          claimed_affiliation_letter(chars: 400),
          resident_letter(
            chars: 500,
            body: "From: resident@example.com\nI am Gregory Halloway and I oppose this bill.\n"
          )
        ]),
        cleaned_testimony_at: 1.hour.ago
      )
    end

    it "refuses the approval and creates no organization from a resident's own name" do
      expect {
        post approve_org_position_bill_path(bill),
          params: {
            org_name: "Gregory Halloway",
            support: "oppose",
            summary: "Opposes the bill.",
            claimed_affiliation_position: 0
          }
      }.not_to change { [Organization.count, OrganizationBillPosition.count] }

      expect(flash[:notice]).to be_nil
    end

    it "approves once the operator sends the confirmed override flag, and logs it" do
      expect {
        post approve_org_position_bill_path(bill),
          params: {
            org_name: "Gregory Halloway",
            support: "oppose",
            summary: "Opposes the bill.",
            claimed_affiliation_position: 0,
            override_private_individual: true
          }
      }.to change(Organization, :count).by(1).and change(OrganizationBillPosition, :count).by(1)

      expect(flash[:notice]).to be_present
      entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").order(:id).last
      expect(entry.payload["private_individual_override"]).to eq(true)
    end
  end

  describe "when the named letter is not in the cleaned artifact" do
    # The claimed-affiliation equivalent of :draft_index_mismatch — a
    # re-run of the clean-testimony stage renumbers letters, so a card held
    # in a stale tab can name a letter that is no longer there.
    let!(:provisioning) do
      create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: "R" * 900,
        cleaned_testimony: claimed_affiliation_artifact([resident_letter(chars: 400, body: "I support this bill.")]),
        cleaned_testimony_at: 1.hour.ago
      )
    end

    it "refuses rather than publishing from a letter it cannot show" do
      expect {
        post approve_org_position_bill_path(bill),
          params: {
            org_name: "Waverly Tenants Alliance",
            support: "support",
            summary: "Backs the bill.",
            claimed_affiliation_position: 7
          }
      }.not_to change { [Organization.count, OrganizationBillPosition.count] }
    end
  end

  describe "an admin asserting a position from their own knowledge" do
    # The third caller class, and the reason the exemption exists at all. It
    # names no draft and no letter, so it draws on no testimony and the
    # testimony rules do not apply to it. Unchanged by any of the above.
    it "still approves with no index and no claimed affiliation" do
      expect {
        post approve_org_position_bill_path(bill),
          params: {
            org_name: "Baltimore Teachers Union",
            support: "support",
            summary: "Supports better schools."
          }
      }.to change(Organization, :count).by(1).and change(OrganizationBillPosition, :count).by(1)

      expect(flash[:notice]).to include("Approved")
    end
  end

  # @lat: [[campaign-approval#What a decision log entry has to identify]]
  describe "the decision log" do
    let!(:provisioning) do
      create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: "R" * 900,
        cleaned_testimony: claimed_affiliation_artifact([
          resident_letter(chars: 400, body: "I support this bill."),
          claimed_affiliation_letter(chars: 400)
        ]),
        cleaned_testimony_at: 1.hour.ago
      )
    end

    def logged_draft_ids
      PipelineActivityLogEntry.where(event_type: "org_position_decision").order(:id)
        .map { |entry| entry.payload["draft_id"] }
    end

    it "records the letter the operator acted on, rather than a nil draft id" do
      post approve_org_position_bill_path(bill),
        params: {
          org_name: "Waverly Tenants Alliance",
          support: "support",
          summary: "Backs the bill on behalf of its members.",
          claimed_affiliation_position: 1
        }

      expect(flash[:notice]).to include("Approved")
      expect(logged_draft_ids).to eq(["#{bill.id}-letter-1"])
    end

    # The tag matters: a bare "#{bill.id}-1" would be indistinguishable from
    # the ordinary draft card's entry for draft index 1 on the same bill, and
    # the two name different things.
    it "does not write a letter position into the same id space as a draft index" do
      post approve_org_position_bill_path(bill),
        params: {
          org_name: "Waverly Tenants Alliance",
          support: "support",
          summary: "Backs the bill on behalf of its members.",
          claimed_affiliation_position: 1
        }

      expect(logged_draft_ids.first).not_to eq("#{bill.id}-1")
    end

    # The third caller class draws on no testimony, so it names nothing this
    # bill's letters contain and nil stays right for it.
    it "still records a nil draft id for an admin asserting a position from their own knowledge" do
      post approve_org_position_bill_path(bill),
        params: {org_name: "Baltimore Teachers Union", support: "support", summary: "Supports better schools."}

      expect(logged_draft_ids).to eq([nil])
    end
  end
end
