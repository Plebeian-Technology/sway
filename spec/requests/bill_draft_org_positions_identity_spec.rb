# frozen_string_literal: true

require "rails_helper"

# @lat: [[draft-org-position-stale-index-trigger#Why the identity guard spec needs more than one draft per bill]]
RSpec.describe "BillDraftOrgPositions draft identity guard", type: :request do
  include_context "SessionDouble"

  before { session_hash[:user_id] = admin.id }

  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill) }

  # The server state partway through that race: A has already been rejected, so what is
  # left is [B, C], while B's card is still on screen holding position 1.
  let!(:provisioning) do
    create(
      :bill_llm_provisioning,
      :with_diff_content,
      bill: bill,
      generation_status: "completed",
      llm_summary: "Test summary",
      llm_full_breakdown: "## Test",
      # @lat: [[testing-the-toolchain#A fixture has to describe a row the system could really produce]]
      extracted_testimony: "Testimony of Org B and Org C, submitted at the hearing.",
      # A cleaned artifact reporting nothing left out, so
      # ApproveOrgPositionService's sixth refusal does not fire here — these examples are about
      # draft identity on reject/edit/approve, not about the coverage gate.
      cleaned_testimony: {
        "version" => 1,
        "text" => "Testimony of Org B and Org C, submitted at the hearing.",
        "counts" => {"raw_chars" => 56, "cleaned_chars" => 56},
        "letters" => [
          {"position" => 0, "character_offset" => 0, "characters" => 56,
           "sender_address" => nil, "sender_domain" => nil,
           "source_kind" => "named_organization", "source_evidence" => nil}
        ],
        "campaign_drafts" => []
      },
      cleaned_testimony_at: Time.zone.now,
      draft_org_positions: [
        {"org_name" => "Org B", "stance" => "support", "summary" => "Supports."},
        {"org_name" => "Org C", "stance" => "oppose", "summary" => "Opposes."}
      ]
    )
  end

  def surviving_draft_org_names
    provisioning.reload.draft_org_positions.map { |d| d["org_name"] }
  end

  describe "reject" do
    it "refuses to delete when the index no longer points at the named draft" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {rejected: true, draft_org_name: "Org B"}

      expect(surviving_draft_org_names).to eq(["Org B", "Org C"])
    end

    it "surfaces a list-has-changed error rather than a success notice on a mismatch" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {rejected: true, draft_org_name: "Org B"}

      expect(response).to redirect_to(positions_bill_creator_path(id: bill.id))
      expect(flash[:notice]).to be_nil
      # inertia-rails carries redirect-time errors in session[:inertia_errors].
      inertia_errors = session[:inertia_errors] || {}
      expect(inertia_errors[:org_position] || inertia_errors["org_position"]).to eq(
        DraftOrgPositionRefusals::LIST_CHANGED
      )
    end

    it "writes no org_position_decision audit entry on a mismatch" do
      expect {
        patch "/bill_draft_org_positions/#{bill.id}-1",
          params: {rejected: true, draft_org_name: "Org B"}
      }.not_to change(PipelineActivityLogEntry, :count)
    end

    it "still deletes when the index and the named draft agree" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {rejected: true, draft_org_name: "Org B"}

      expect(surviving_draft_org_names).to eq(["Org C"])
      expect(flash[:notice]).to eq("Rejected Org B on #{bill.external_id}.")
    end
  end

  # @lat: [[bill-draft-org-positions-controller#Why both branches re-check identity against the entry at the index]]
  # @lat: [[draft-org-position-identity#draft_token: an identity worked out from content]]
  # A position number does not name a draft: it shifts by design, and the audit entry
  # reads whatever entry the number lands on.
  describe "a caller that asserts no draft identity (C2-WR-03)" do
    it "refuses to reject" do
      patch "/bill_draft_org_positions/#{bill.id}-0", params: {rejected: true}

      expect(surviving_draft_org_names).to eq(["Org B", "Org C"])
    end

    it "refuses to edit" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {stance: "neutral", summary: "Amended."}

      expect(provisioning.reload.draft_org_positions).to eq([
        {"org_name" => "Org B", "stance" => "support", "summary" => "Supports."},
        {"org_name" => "Org C", "stance" => "oppose", "summary" => "Opposes."}
      ])
    end

    it "writes no audit entry" do
      expect {
        patch "/bill_draft_org_positions/#{bill.id}-0", params: {rejected: true}
      }.not_to change(PipelineActivityLogEntry, :count)
    end

    # The fix here differs from the fix for a mismatched name, so the refusal has to
    # differ too. A caller that named nothing gains nothing by reloading; it has to
    # name the draft. Telling it "this draft list has changed" would send it round a
    # loop with no way out.
    it "names the actual remedy rather than telling the caller to reload" do
      patch "/bill_draft_org_positions/#{bill.id}-0", params: {rejected: true}

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("identity_required")
    end

    it "refuses to approve" do
      provisioning.update!(supplemental_testimony: "Testimony of Org B, in support.")

      post "/bills/#{bill.id}/approve_org_position",
        params: {org_name: "Org B", support: "support", summary: "Supports.", index: 0}

      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(surviving_draft_org_names).to eq(["Org B", "Org C"])
    end

    # The one exception that stays, and why: a caller that sends no :index is not
    # pointing at any draft and cannot destroy one. It is stating a position from its
    # own inputs, which is what BillsController#approve_org_position does. The rule about
    # naming a draft is about promoting a draft the pipeline built from testimony.
    it "still lets an index-less approve through" do
      provisioning.update!(supplemental_testimony: "Testimony of Org D, in support.")

      post "/bills/#{bill.id}/approve_org_position",
        params: {org_name: "Org D", support: "support", summary: "Supports."}

      expect(OrganizationBillPosition.where(bill: bill).count).to eq(1)
      expect(surviving_draft_org_names).to eq(["Org B", "Org C"])
    end
  end

  # @lat: [[bill-draft-org-positions-controller#Why this endpoint's admin guard is tested with a non-real bill id, and why the message says "look at the list", not "reload"]]
  describe "a PATCH that names no change (C2-IN-04)" do
    it "writes no audit entry" do
      expect {
        patch "/bill_draft_org_positions/#{bill.id}-0",
          params: {draft_org_name: "Org B"}
      }.not_to change(PipelineActivityLogEntry, :count)
    end

    it "does not tell the operator something was updated" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {draft_org_name: "Org B"}

      expect(flash[:notice]).to be_nil
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("no_change")
    end

    # A blank-string edit is a real edit: clearing a summary is something an
    # operator does on purpose. Only the absence of every field is a no-op.
    it "still accepts an edit that blanks a field" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {draft_org_name: "Org B", summary: ""}

      expect(provisioning.reload.draft_org_positions.first["summary"]).to eq("")
    end
  end

  describe "edit" do
    # `drafts[index] = entry` goes wrong the same way `delete_at(index)` does: an
    # out-of-date position number folds one draft's edits into a different draft.
    it "refuses to merge edits into the draft sitting at a stale index" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {draft_org_name: "Org B", stance: "neutral", summary: "Amended."}

      expect(provisioning.reload.draft_org_positions).to eq([
        {"org_name" => "Org B", "stance" => "support", "summary" => "Supports."},
        {"org_name" => "Org C", "stance" => "oppose", "summary" => "Opposes."}
      ])
    end

    it "still applies the edit when the index and the named draft agree" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {draft_org_name: "Org C", stance: "support", summary: "Amended."}

      entry = provisioning.reload.draft_org_positions.last
      # @lat: [[explanation/llm-summaries#Whose words a stored summary records]]
      expect(entry.except(BillLlmProvisioning::DRAFT_SUMMARY_EDITED_KEY)).to eq(
        {"org_name" => "Org C", "stance" => "support", "summary" => "Amended."}
      )
      expect(BillLlmProvisioning.draft_summary_edited?(entry)).to be(true)
    end

    it "drops the summary of a draft edited to neutral, and keeps the position" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {draft_org_name: "Org C", stance: "neutral", summary: "Amended."}

      entry = provisioning.reload.draft_org_positions.last
      expect(entry["org_name"]).to eq("Org C")
      expect(entry["stance"]).to eq("neutral")
      expect(entry["summary"]).to be_nil
    end

    it "drops the summary of a draft that is already neutral when anything else is edited" do
      provisioning.update!(draft_org_positions: [
        {"org_name" => "Org B", "stance" => "support", "summary" => "Supports."},
        {"org_name" => "Org C", "stance" => "neutral", "summary" => "Says nothing either way."}
      ])

      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {draft_org_name: "Org C", org_name: "Org C Renamed"}

      entry = provisioning.reload.draft_org_positions.last
      expect(entry["org_name"]).to eq("Org C Renamed")
      expect(entry["summary"]).to be_nil
    end
  end

  # @lat: [[draft-org-position-identity#draft_org_positions_for_client: the version the browser sees]]
  describe "duplicate org names" do
    let!(:provisioning) do
      create(
        :bill_llm_provisioning,
        :with_diff_content,
        bill: bill,
        generation_status: "completed",
        llm_summary: "Test summary",
        llm_full_breakdown: "## Test",
        draft_org_positions: [
          {"org_name" => "Renters United", "stance" => "support", "summary" => "The coalition supports."},
          {"org_name" => "Renters United", "stance" => "oppose", "summary" => "A member testified against."}
        ]
      )
    end

    # The same race described at the top of this file, with the two survivors sharing a
    # name: the card for position 0 is clicked while it still holds position 1.
    it "refuses a stale index that lands on a same-named sibling" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {rejected: true, draft_org_name: "Renters United", draft_token: BillLlmProvisioning.draft_token(provisioning.reload.draft_org_positions[0])}

      expect(surviving_draft_org_names).to eq(["Renters United", "Renters United"])
      expect(provisioning.reload.draft_org_positions.pluck("stance")).to eq(%w[support oppose])
    end

    it "still deletes the entry the token actually names" do
      patch "/bill_draft_org_positions/#{bill.id}-1",
        params: {rejected: true, draft_org_name: "Renters United", draft_token: BillLlmProvisioning.draft_token(provisioning.reload.draft_org_positions[1])}

      expect(provisioning.reload.draft_org_positions).to eq([
        {"org_name" => "Renters United", "stance" => "support", "summary" => "The coalition supports."}
      ])
    end
  end

  # @lat: [[internal-draft-marks#DRAFT_EVIDENCE_RETRACTED_KEY#Why reject and edit are unaffected by the mark, and why edit must not erase it]]
  describe "evidence-retracted drafts (B4-CR-02)" do
    let!(:retracted_provisioning) do
      provisioning.update!(draft_org_positions: [
        {"org_name" => "Org B", "stance" => "support", "summary" => "Supports.",
         BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY => "2026-07-01T00:00:00Z"},
        {"org_name" => "Org C", "stance" => "oppose", "summary" => "Opposes."}
      ])
      provisioning
    end

    it "keeps the mark across an edit" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {org_name: "Org B", stance: "support", summary: "Reworded.", draft_org_name: "Org B"}

      entry = retracted_provisioning.reload.draft_org_positions.first
      expect(entry["summary"]).to eq("Reworded.")
      expect(entry[BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq("2026-07-01T00:00:00Z")
    end

    it "lets the operator reject it" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {rejected: true, draft_org_name: "Org B"}

      expect(surviving_draft_org_names).to eq(["Org C"])
    end
  end

  # @lat: [[org-position-draft-identity-exemption#Cross-file consistency]]
  describe "empty-string draft_org_name (C2-IN-03)" do
    let!(:provisioning) do
      create(
        :bill_llm_provisioning,
        :with_diff_content,
        bill: bill,
        generation_status: "completed",
        llm_summary: "Test summary",
        llm_full_breakdown: "## Test",
        supplemental_testimony: "Testimony of Org B, submitted in support.",
        draft_org_positions: [
          {"org_name" => "Org B", "stance" => "support", "summary" => "Supports."},
          {"org_name" => "Org C", "stance" => "oppose", "summary" => "Opposes."}
        ]
      )
    end

    it "means the same thing to reject and to approve" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {rejected: true, draft_org_name: ""}
      reject_acted = surviving_draft_org_names == ["Org C"]

      provisioning.update!(draft_org_positions: [
        {"org_name" => "Org B", "stance" => "support", "summary" => "Supports."},
        {"org_name" => "Org C", "stance" => "oppose", "summary" => "Opposes."}
      ])
      post "/bills/#{bill.id}/approve_org_position",
        params: {org_name: "Org B", support: "support", summary: "Supports.",
                 index: 0, draft_org_name: ""}
      approve_acted = OrganizationBillPosition.where(bill: bill).count == 1

      expect(approve_acted).to eq(reject_acted)
    end
  end

  # The identity check ran before the change, with nothing holding the row in between,
  # and the write then put the entire list back. Anyone who wrote in that gap was simply
  # overwritten — an update lost on exactly the data this check exists to protect.
  describe "concurrent write in the check-to-write window" do
    # @lat: [[org-position-approval-guard-chain#The lock that makes the re-check authoritative]]
    it "does not clobber a draft committed before the mutation took the row" do
      allow_any_instance_of(BillDraftOrgPositionsController) # rubocop:disable RSpec/AnyInstance
        .to receive(:apply_draft_decision).and_wrap_original do |original, locked_provisioning, index, rejecting|
          BillLlmProvisioning.find(provisioning.id).update!(
            draft_org_positions: provisioning.draft_org_positions + [
              {"org_name" => "Org D", "stance" => "neutral", "summary" => "Late arrival."}
            ]
          )
          original.call(locked_provisioning, index, rejecting)
        end

      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {rejected: true, draft_org_name: "Org B"}

      expect(surviving_draft_org_names).to eq(["Org C", "Org D"])
    end
  end

  # @lat: [[org-position-approval-guard-chain#The pre-check / re-check split#run_in_flight?]]
  describe "approving a draft while a run is in flight" do
    # The whole point is a request from a tab that has not learned about the
    # run yet, so it carries a perfectly valid draft_token and index.
    def approve_org_b
      post "/bills/#{bill.id}/approve_org_position",
        params: {org_name: "Org B", support: "support", summary: "Supports.",
                 index: 0, draft_org_name: "Org B"}
    end

    before { provisioning.update!(supplemental_testimony: "Testimony of Org B, in support.") }

    # Both in-flight statuses, because fixing one arm of a two-arm guard is a
    # recurring defect shape in this phase and BillCreatorLlmSummaryStatus
    # derives runInFlight from both.
    ["pending", "generating"].each do |status|
      context "when the row is #{status}" do
        before { provisioning.update!(generation_status: status) }

        it "publishes no organization position" do
          expect { approve_org_b }.not_to change(OrganizationBillPosition, :count)
        end

        it "leaves the draft on the row rather than deleting it" do
          approve_org_b

          expect(surviving_draft_org_names).to eq(["Org B", "Org C"])
        end

        it "says what happened and what to do next" do
          approve_org_b

          expect(response).to redirect_to(positions_bill_creator_path(bill))
          expect(flash[:notice]).to be_nil
          # inertia-rails carries redirect-time errors in
          # session[:inertia_errors], with the key symbolized or not depending
          # on how the hash was built — the sibling example above reads both.
          inertia_errors = session[:inertia_errors] || {}
          expect((inertia_errors[:org_position] || inertia_errors["org_position"]).to_s)
            .to match(/new summary .* will replace these drafts/i)
        end
      end
    end

    # The other direction, so the refusal cannot be over-corrected into "no
    # Approve on any row with a status". A settled row still publishes.
    it "still publishes on a completed row" do
      provisioning.update!(generation_status: "completed")

      expect { approve_org_b }.to change(OrganizationBillPosition, :count).by(1)
      expect(surviving_draft_org_names).to eq(["Org C"])
    end
  end

  # Approving copies a draft's text into the new position's
  # ai_summary column, which means "the model's own words". This mark is what
  # keeps that column from being handed a person's words instead.
  describe "the summary-edited mark" do
    it "marks a draft whose summary the operator rewrote" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {summary: "A person rewrote this.", draft_org_name: "Org B"}

      entry = provisioning.reload.draft_org_positions[0]
      expect(entry["summary"]).to eq("A person rewrote this.")
      expect(BillLlmProvisioning.draft_summary_edited?(entry)).to be(true)
    end

    # The two fields move APART here: the name changes and the summary does
    # not. A mark stamped on any edit would pass a fixture that changed both.
    it "leaves a rename unmarked, because the model's sentence is untouched" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {org_name: "Org B Renamed", draft_org_name: "Org B"}

      entry = provisioning.reload.draft_org_positions[0]
      expect(entry["org_name"]).to eq("Org B Renamed")
      expect(entry["summary"]).to eq("Supports.")
      expect(BillLlmProvisioning.draft_summary_edited?(entry)).to be(false)
    end

    it "leaves a stance correction unmarked for the same reason" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {stance: "oppose", draft_org_name: "Org B"}

      entry = provisioning.reload.draft_org_positions[0]
      expect(entry["stance"]).to eq("oppose")
      expect(BillLlmProvisioning.draft_summary_edited?(entry)).to be(false)
    end

    it "marks only the draft that was edited, never its siblings" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {summary: "A person rewrote this.", draft_org_name: "Org B"}

      drafts = provisioning.reload.draft_org_positions
      expect(BillLlmProvisioning.draft_summary_edited?(drafts[0])).to be(true)
      expect(BillLlmProvisioning.draft_summary_edited?(drafts[1])).to be(false)
    end

    # The mark records when the text stopped being the model's, and that
    # moment does not move because somebody edited it again.
    it "keeps the first mark when the same draft is edited a second time" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {summary: "First rewrite.", draft_org_name: "Org B"}
      first_mark = provisioning.reload.draft_org_positions[0][BillLlmProvisioning::DRAFT_SUMMARY_EDITED_KEY]

      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {summary: "Second rewrite.", draft_org_name: "Org B"}

      entry = provisioning.reload.draft_org_positions[0]
      expect(entry["summary"]).to eq("Second rewrite.")
      expect(entry[BillLlmProvisioning::DRAFT_SUMMARY_EDITED_KEY]).to eq(first_mark)
    end
  end
end
