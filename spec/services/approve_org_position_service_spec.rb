# frozen_string_literal: true

require "rails_helper"

# Unit coverage for the org-position approval logic pulled out of
# BillsController#approve_org_position; the request spec covers HTTP mapping,
# this pins service outcomes and side effects.
RSpec.describe ApproveOrgPositionService do
  include TestimonySpecHelpers

  # The sixth refusal fires whenever
  # Testimony::CoverageReport finds a real cut nobody has acknowledged — true
  # for nearly every bill in this file that carries testimony but no
  # cleaned_testimony artifact (:with_testimony and friends set up exactly
  # that shape, and never_run ALWAYS reads as a gap, size aside).
  # None of the examples below this line are testing the coverage gate, so
  # it is stubbed off here by default; "the coverage acknowledgement guard"
  # block turns it back on to test the real thing.
  before do
    allow(Testimony::CoverageReport).to receive(:coverage_gap?).and_return(false)
  end

  it "creates the org + an active position and returns :approved" do
    bill = create(:bill)

    outcome = described_class.new(
      bill: bill, actor: create(:user),
      org_name: "Brand New Org", support: "support", summary: "Backs the bill"
    ).call

    expect(outcome).to eq(:approved)
    org = Organization.find_by(name: "Brand New Org", sway_locale: bill.sway_locale) #: Organization
    position = OrganizationBillPosition.find_by(bill: bill, organization: org) #: OrganizationBillPosition
    expect(position.support).to eq(OrganizationBillPosition.normalize_support("support"))
    expect(position.summary).to eq("Backs the bill")
    expect(position.active).to be(true)
  end

  it "fuzzy-matches an existing org instead of creating a duplicate" do
    bill = create(:bill)
    create(:organization, name: "Sierra Club", sway_locale: bill.sway_locale)

    expect {
      described_class.new(
        bill: bill, actor: create(:user),
        org_name: "sierra club", support: "oppose", summary: "Opposes"
      ).call
    }.not_to change(Organization, :count)
  end

  it "returns :org_name_required when the name is blank after strip" do
    bill = create(:bill)

    outcome = described_class.new(
      bill: bill, actor: create(:user), org_name: "   ", support: "support", summary: "x"
    ).call

    expect(outcome).to eq(:org_name_required)
    expect(OrganizationBillPosition.count).to eq(0)
  end

  # @lat: [[organization-position-removal#A refusal reaches the operator as a message, not a 500]]
  it "returns :summary_required when the summary is blank after strip, instead of raising" do
    bill = create(:bill)

    outcome = described_class.new(
      bill: bill, actor: create(:user), org_name: "Some Org", support: "support", summary: "   "
    ).call

    expect(outcome).to eq(:summary_required)
    expect(OrganizationBillPosition.count).to eq(0)
  end

  it "returns :invalid_stance for an unrecognized stance" do
    bill = create(:bill)

    outcome = described_class.new(
      bill: bill, actor: create(:user), org_name: "Some Org", support: "maybe", summary: "x"
    ).call

    expect(outcome).to eq(:invalid_stance)
    expect(Organization.where(name: "Some Org").count).to eq(0)
  end

  it "removes the approved draft from provisioning at the given index" do
    bill = create(:bill)
    create(:bill_llm_provisioning, :with_testimony, bill: bill,
      draft_org_positions: [{"org_name" => "First"}, {"org_name" => "Second"}])

    described_class.new(
      bill: bill, actor: create(:user),
      org_name: "First", support: "support", summary: "x", index: "0", draft_org_name: "First"
    ).call

    expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq([{"org_name" => "Second"}])
  end

  # Every other example sends :index as TEXT; the card sends a JSON number
  # instead. Conflating the two once broke every Approve click while this
  # file stayed green.
  it "removes the approved draft when :index arrives as a number, the way the card sends it" do
    bill = create(:bill)
    create(:bill_llm_provisioning, :with_testimony, bill: bill,
      draft_org_positions: [{"org_name" => "First"}, {"org_name" => "Second"}])

    outcome = described_class.new(
      bill: bill, actor: create(:user),
      org_name: "First", support: "support", summary: "x", index: 0, draft_org_name: "First"
    ).call

    expect(outcome).to eq(:approved)
    expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq([{"org_name" => "Second"}])
    expect(OrganizationBillPosition.where(bill: bill).count).to eq(1)
  end

  # C-CR-04: the FE index is a position in the RENDERED array (filters out
  # rejected entries); the server indexes the raw array. The submitted draft
  # identity catches it when the two diverge.
  describe "draft identity guard (C-CR-04)" do
    it "refuses to touch anything when the entry at :index is not the submitted draft" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"rejected" => true}, {"org_name" => "A"}, {"org_name" => "B"}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "B", support: "support", summary: "x", index: "1", draft_org_name: "B"
      ).call

      expect(outcome).to eq(:draft_index_mismatch)
      expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq(
        [{"rejected" => true}, {"org_name" => "A"}, {"org_name" => "B"}]
      )
      expect(Organization.where(name: "B").count).to eq(0)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
    end

    it "deletes the right draft when the index and the submitted draft identity agree" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"rejected" => true}, {"org_name" => "A"}, {"org_name" => "B"}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "B", support: "support", summary: "x", index: "2", draft_org_name: "B"
      ).call

      expect(outcome).to eq(:approved)
      expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq(
        [{"rejected" => true}, {"org_name" => "A"}]
      )
    end

    it "still approves a draft the operator renamed before approving" do
      # org_name is editable in the card (local until Approve), so the
      # identity token is the PRISTINE draft name, not the submitted one.
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"org_name" => "Typo'd Org"}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Corrected Org", support: "support", summary: "x",
        index: "0", draft_org_name: "Typo'd Org"
      ).call

      expect(outcome).to eq(:approved)
      expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq([])
      expect(Organization.where(name: "Corrected Org").count).to eq(1)
    end
  end

  # B2-IN-01: org_name is not an identifier — draft_org_positions allows
  # duplicate names, so the identity token can't tell two same-named drafts
  # apart, and the wrong one gets destroyed.
  describe "draft identity guard with duplicate org names (B2-IN-01)" do
    let(:bill) { create(:bill) }
    let!(:provisioning) do
      create(:bill_llm_provisioning, :with_testimony, bill: bill, draft_org_positions: [
        {"org_name" => "Renters United", "stance" => "support", "summary" => "The coalition supports."},
        {"org_name" => "Renters United", "stance" => "oppose", "summary" => "A member testified against."}
      ])
    end

    it "refuses a stale index that lands on a same-named sibling" do
      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Renters United", support: "support", summary: "x",
        index: "1", draft_org_name: "Renters United", draft_token: BillLlmProvisioning.draft_token(provisioning.reload.draft_org_positions[0])
      ).call

      expect(outcome).to eq(:draft_index_mismatch)
      expect(provisioning.reload.draft_org_positions.pluck("stance")).to eq(%w[support oppose])
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
    end

    it "approves the entry the token actually names" do
      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Renters United", support: "oppose", summary: "x",
        index: "1", draft_org_name: "Renters United", draft_token: BillLlmProvisioning.draft_token(provisioning.reload.draft_org_positions[1])
      ).call

      expect(outcome).to eq(:approved)
      expect(provisioning.reload.draft_org_positions).to eq([
        {"org_name" => "Renters United", "stance" => "support", "summary" => "The coalition supports."}
      ])
    end
  end

  # B2-IN-02: the guard ran before the transaction opened, and
  # #delete_approved_draft wrote the whole array back from a memoized read,
  # losing a concurrent writer's change.
  describe "concurrent write in the check-to-write window (B2-IN-02)" do
    it "does not clobber a draft appended after the guard ran" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"org_name" => "A"}, {"org_name" => "B"}])

      service = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "B", support: "support", summary: "x", index: "1", draft_org_name: "B"
      )
      allow(service).to receive(:draft_index_mismatch?).and_wrap_original do |original, drafts = nil|
        result = original.call(drafts)
        BillLlmProvisioning.find(provisioning.id).update!(
          draft_org_positions: [{"org_name" => "A"}, {"org_name" => "B"}, {"org_name" => "C"}]
        )
        result
      end

      expect(service.call).to eq(:approved)
      expect(provisioning.reload.draft_org_positions).to eq([{"org_name" => "A"}, {"org_name" => "C"}])
    end
  end

  # B4-CR-02: FetchHearingsService's :retract stamps surviving
  # drafts. Approve must refuse a stamped draft — the credibility risk
  # REAS-01 prevents.
  describe "evidence-retracted drafts (B4-CR-02)" do
    it "refuses to approve a draft whose evidence was retracted" do
      bill = create(:bill)
      drafts = [
        {"org_name" => "ACME", "stance" => "support", "summary" => "Backs it.",
         BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY => "2026-07-01T00:00:00Z"}
      ]
      create(:bill_llm_provisioning, :with_testimony, bill: bill, draft_org_positions: drafts)

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:evidence_retracted)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(Organization.where(name: "ACME").count).to eq(0)
      # Nothing destroyed: the draft is still there for the operator to reject
      # or to recover by regenerating.
      expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq(drafts)
    end

    # The refusal is index-addressed, so an unmarked sibling of a marked draft
    # is unaffected — this is a per-draft mark, not a per-bill freeze.
    it "still approves an unmarked sibling draft" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill, draft_org_positions: [
        {"org_name" => "ACME", "stance" => "support", "summary" => "Backs it.",
         BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY => "2026-07-01T00:00:00Z"},
        {"org_name" => "Beta", "stance" => "oppose", "summary" => "Against it."}
      ])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Beta", support: "oppose", summary: "Against it.", index: "1", draft_org_name: "Beta"
      ).call

      expect(outcome).to eq(:approved)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(1)
    end

    # B2-IN-02's rule applied here: the pre-transaction check is only an
    # optimisation; a retract landing in the check-to-write window must
    # still refuse and roll back.
    it "refuses a mark that lands after the pre-check ran, rolling back the chain" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, :with_testimony, bill: bill, draft_org_positions: [
        {"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}
      ])

      service = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      )
      allow(service).to receive(:draft_evidence_retracted?).and_wrap_original do |original, drafts = nil|
        result = original.call(drafts)
        BillLlmProvisioning.find(provisioning.id).update!(draft_org_positions: [
          {"org_name" => "ACME", "stance" => "support", "summary" => "Backs it.",
           BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY => "2026-07-01T00:00:00Z"}
        ])
        result
      end

      expect(service.call).to eq(:evidence_retracted)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(Organization.where(name: "ACME").count).to eq(0)
      expect(provisioning.reload.draft_org_positions.first).to have_key(
        BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY
      )
    end
  end

  # A2-CR-01 / C2-CR-01: REAS-01 guarded writes to draft_org_positions but
  # not testimony destroyed under existing drafts. Blocking approval is the
  # remedy; drafts stay untouched.
  describe "bill-level testimony gate (A2-CR-01 / C2-CR-01)" do
    it "refuses a draft whose bill has no testimony left, through the real Clear path" do
      bill = create(:bill)
      drafts = [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}]
      provisioning = create(:bill_llm_provisioning, bill: bill,
        supplemental_testimony: "Testimony of ACME, submitted in support of the bill.",
        draft_org_positions: drafts)

      # The operator's Clear — PATCH /bills/:id/supplemental_testimony, the
      # production path, not a hand-written column update.
      expect(
        UpdateSupplementalTestimonyService.new(bill: bill, clear_supplemental_testimony: true).call
      ).to eq(:updated)

      provisioning.reload
      expect(provisioning.testimony_present?).to be(false)
      # @lat: [[hearing-testimony-census#Retracting evidence retires the conclusions drawn from it]]
      expect(BillLlmProvisioning.draft_evidence_retracted?(provisioning.draft_org_positions.first)).to be(true)

      outcome = described_class.new(
        bill: bill.reload, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:evidence_retracted)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(Organization.where(name: "ACME").count).to eq(0)
      # Nothing destroyed: the draft survives for Reject, Edit, or regeneration.
      # It now carries the mark, so it is the same draft plus that key.
      surviving = provisioning.reload.draft_org_positions
      expect(surviving.length).to eq(1)
      expect(surviving.first.except(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY)).to eq(drafts.first)
    end

    # The bill-level gate on its own, reached without a per-entry mark — the
    # pre-phase-63 residual shape: drafts on a row that never had testimony,
    # so nothing ever marked them.
    it "refuses an unmarked draft when the bill has no testimony at all" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill,
        supplemental_testimony: nil, extracted_testimony: nil,
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

      expect(provisioning.testimony_present?).to be(false)
      expect(BillLlmProvisioning.draft_evidence_retracted?(provisioning.draft_org_positions.first)).to be(false)

      outcome = described_class.new(
        bill: bill.reload, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:no_testimony)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
    end

    it "approves the same draft once the testimony is back" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill,
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

      expect(
        described_class.new(
          bill: bill, actor: create(:user),
          org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
        ).call
      ).to eq(:no_testimony)

      provisioning.update!(supplemental_testimony: "Testimony of ACME, re-pasted by the operator.")

      expect(
        described_class.new(
          bill: bill.reload, actor: create(:user),
          org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
        ).call
      ).to eq(:approved)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(1)
    end

    it "accepts extracted_testimony as evidence, not only the operator's paste" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony extracted from the hearing packet.",
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:approved)
    end

    # Same exemption as the per-entry guard: a caller with no :index asserts
    # its own position (what BillsController#approve_org_position does), not
    # one drawn from testimony — what REAS-01 governs.
    it "leaves an index-less caller alone on a bill with no testimony" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [{"org_name" => "ACME"}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Direct Admin Assertion", support: "support", summary: "x"
      ).call

      expect(outcome).to eq(:approved)
    end

    # B2-IN-02's rule again: the pre-transaction check is only an optimisation.
    # A Clear from another tab landing in the check-to-write window must still
    # refuse, rolling back the whole mutation chain.
    it "refuses a clear that lands after the pre-check ran, rolling back the chain" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill,
        supplemental_testimony: "Testimony of ACME, submitted in support of the bill.",
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

      service = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      )
      allow(service).to receive(:bill_testimony_missing?).and_wrap_original do |original, provisioning_row = nil|
        result = original.call(provisioning_row)
        UpdateSupplementalTestimonyService.new(
          bill: Bill.find(bill.id), clear_supplemental_testimony: true
        ).call
        result
      end

      # Clear now also stamps, and the per-entry check answers
      # first, so the refusal is the more specific :evidence_retracted. This
      # example is about the ROLLBACK the assertions below still pin.
      expect(service.call).to eq(:evidence_retracted)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(Organization.where(name: "ACME").count).to eq(0)
      expect(provisioning.reload.draft_org_positions.length).to eq(1)
    end
  end

  # D-WR-01: the bill-level gate only checks whether testimony is ABSENT, so
  # REPLACING it trips no guard — Approve can publish a stance drawn from
  # evidence never about the bill.
  describe "evidence replaced under existing drafts (D-WR-01)" do
    it "retracts the drafts when the replacement arrives on the PATCH endpoint's path" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill,
        supplemental_testimony: "Testimony submitted on a DIFFERENT bill, pasted by mistake.",
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

      expect(
        UpdateSupplementalTestimonyService.new(
          bill: bill,
          supplemental_testimony: "Testimony of ACME, submitted on THIS bill."
        ).call
      ).to eq(:updated)

      # The premise: the bill-level gate CANNOT fire here, because the bill
      # still has testimony. Only the per-entry mark can refuse this.
      expect(provisioning.reload.testimony_present?).to be(true)

      outcome = described_class.new(
        bill: bill.reload, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:evidence_retracted)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(Organization.where(name: "ACME").count).to eq(0)
      # Marked, never destroyed — the same disposition every other REAS-01
      # refusal takes. Reject and Edit stay live on the card.
      expect(provisioning.reload.draft_org_positions.first["org_name"]).to eq("ACME")
    end

    # The second of the two writers of the column. Both route through
    # SupplementalTestimonyWrite, and pinning only one is the "fixed at one
    # call site when two exist" shape this phase keeps producing.
    it "retracts the drafts when the replacement rides along with a Generate" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill,
        supplemental_testimony: "Testimony submitted on a DIFFERENT bill, pasted by mistake.",
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

      expect(
        GenerateBillSummaryService.new(
          bill: bill, actor: create(:user),
          supplemental_testimony: "Testimony of ACME, submitted on THIS bill."
        ).call
      ).to eq(:enqueued)

      expect(provisioning.reload.testimony_present?).to be(true)

      outcome = described_class.new(
        bill: bill.reload, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:evidence_retracted)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
    end

    # The boundary, stated as a decision: an operator ADDING to their paste
    # has withdrawn nothing, since every word the drafts were drawn from is
    # still on the row.
    it "leaves the drafts approvable when the operator only appends to the paste" do
      bill = create(:bill)
      stored = "Testimony of ACME, submitted in support of the bill."
      provisioning = create(:bill_llm_provisioning, bill: bill,
        supplemental_testimony: stored,
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

      UpdateSupplementalTestimonyService.new(
        bill: bill,
        supplemental_testimony: "#{stored}\n\nTestimony of Beta Coalition, also in support."
      ).call

      expect(
        BillLlmProvisioning.draft_evidence_retracted?(provisioning.reload.draft_org_positions.first)
      ).to be(false)

      expect(
        described_class.new(
          bill: bill.reload, actor: create(:user),
          org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
        ).call
      ).to eq(:approved)
    end

    # A FIRST paste is not a replacement — there was no stored testimony to
    # destroy. Drafts on such a row were drawn from extracted_testimony (or
    # nothing), and neither is touched by this write.
    it "leaves the drafts alone on a first paste onto a row with no stored testimony" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony extracted from the hearing packet.",
        supplemental_testimony: nil,
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

      UpdateSupplementalTestimonyService.new(
        bill: bill, supplemental_testimony: "Additional testimony the operator found."
      ).call

      expect(
        BillLlmProvisioning.draft_evidence_retracted?(provisioning.reload.draft_org_positions.first)
      ).to be(false)
    end

    # @lat: [[hearing-testimony-census#Retracting evidence retires the conclusions drawn from it]]
    it "stamps the drafts on an explicit clear, so Approve refuses" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill,
        supplemental_testimony: "Testimony of ACME, submitted in support of the bill.",
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

      UpdateSupplementalTestimonyService.new(bill: bill, clear_supplemental_testimony: true).call

      provisioning.reload
      expect(provisioning.supplemental_testimony).to be_nil
      expect(BillLlmProvisioning.draft_evidence_retracted?(provisioning.draft_org_positions.first)).to be(true)
      # Marked, never destroyed — the disposition every REAS-01 refusal takes.
      expect(provisioning.draft_org_positions.first["org_name"]).to eq("ACME")
    end

    # Now pinned as actual behaviour: re-pasting does not restore
    # approvability, since nothing proves it matches what was removed.
    # Regenerate or Reject are the two ways out.
    it "keeps refusing after a re-paste, because the mark survives it" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill,
        supplemental_testimony: "Testimony of ACME, submitted in support of the bill.",
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

      UpdateSupplementalTestimonyService.new(bill: bill, clear_supplemental_testimony: true).call
      UpdateSupplementalTestimonyService.new(
        bill: bill, supplemental_testimony: "Testimony of ACME, submitted in support of the bill."
      ).call

      expect(
        described_class.new(
          bill: bill.reload, actor: create(:user),
          org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
        ).call
      ).not_to eq(:approved)
    end
  end

  # D-CR-01: an :index resolving to NO draft made every guard answer "no
  # objection," and the in-lock re-check bailed via `next` — publishing a
  # public position from a draft that doesn't exist.
  describe "unresolvable :index (D-CR-01)" do
    it "publishes nothing for an index past the end of the draft list" do
      # The operator rejected "Alpha", shrinking the array from 2 to 1; the
      # in-flight Approve for the card at index 1 arrives with its pre-delete
      # index.
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"org_name" => "Gamma"}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Beta", support: "oppose", summary: "Against it.",
        index: "1", draft_org_name: "Beta"
      ).call

      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(Organization.where(name: "Beta").count).to eq(0)
      expect(outcome).to eq(:draft_index_mismatch)
      # The surviving draft is untouched — nothing was destroyed either.
      expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq([{"org_name" => "Gamma"}])
    end

    it "publishes nothing for an unparseable index naming an org with no draft" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"org_name" => "Gamma"}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Never Testified LLC", support: "support", summary: "x",
        index: "abc", draft_org_name: "Never Testified LLC", draft_token: "deadbeef"
      ).call

      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(Organization.where(name: "Never Testified LLC").count).to eq(0)
      expect(outcome).to eq(:draft_index_mismatch)
    end

    # A negative index must never be resolved by Ruby's wrap-around
    # `Array#[]` — "-1" would otherwise name the LAST draft, which is a
    # different draft than the operator saw.
    it "publishes nothing for a negative index" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"org_name" => "Gamma"}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Gamma", support: "support", summary: "x",
        index: "-1", draft_org_name: "Gamma"
      ).call

      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(outcome).to eq(:draft_index_mismatch)
      expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq([{"org_name" => "Gamma"}])
    end

    # The pre-transaction check is only an optimisation; a concurrent reject
    # shrinking the array past the operator's index in that window must
    # still roll back — the D-CR-01 path.
    it "refuses a shrink that lands after the pre-check ran, rolling back the chain" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"org_name" => "Alpha"}, {"org_name" => "Beta"}])

      service = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Beta", support: "oppose", summary: "Against it.",
        index: "1", draft_org_name: "Beta"
      )
      allow(service).to receive(:bill_testimony_missing?).and_wrap_original do |original, provisioning_row = nil|
        result = original.call(provisioning_row)
        BillLlmProvisioning.find(provisioning.id).update!(draft_org_positions: [])
        result
      end

      outcome = service.call

      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(Organization.where(name: "Beta").count).to eq(0)
      expect(outcome).to eq(:draft_index_mismatch)
    end

    # The deliberate exemption survives: a caller with no :index asserts a
    # position from its own inputs, not the pipeline's. Re-pinned so
    # D-CR-01's fix can't narrow it by accident.
    it "still approves an index-less caller on a bill whose drafts are unrelated" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"org_name" => "Gamma"}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Direct Admin Assertion", support: "support", summary: "x"
      ).call

      expect(outcome).to eq(:approved)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(1)
      expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq([{"org_name" => "Gamma"}])
    end

    # ...but the exemption stops once a caller NAMES a draft: dropping the
    # index then skips every evidence rule, letting Approve publish while the
    # draft stays on screen.
    it "refuses a caller that names a draft but not where it sits" do
      bill = create(:bill)
      provisioning = create(
        :bill_llm_provisioning, bill: bill,
        draft_org_positions: [{"org_name" => "Delta", "evidence_retracted_at" => 1.hour.ago.iso8601}]
      )
      token = BillLlmProvisioning.draft_token(provisioning.draft_org_positions.first)

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Delta", support: "support", summary: "x",
        draft_token: token
      ).call

      expect(outcome).to eq(:draft_index_required)
      # Nothing published, and the draft is still there to be dealt with
      # properly.
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(provisioning.reload.draft_org_positions.length).to eq(1)
    end

    it "refuses the same request when it names the draft by name instead of token" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [{"org_name" => "Delta"}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Delta", support: "support", summary: "x",
        draft_org_name: "Delta"
      ).call

      expect(outcome).to eq(:draft_index_required)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
    end
  end

  # The mutation chain is transactional — a failure in any later step
  # rolls the whole thing back so no orphan Organization / position survives.
  it "rolls back a freshly-created org when a later step in the chain fails" do
    bill = create(:bill)
    # Force the final op (audit log) to raise AFTER org/position/draft writes.
    allow(PipelineActivityLogger).to receive(:log_org_position_decision!).and_raise(RuntimeError.new("boom"))

    expect {
      described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Rollback Org", support: "support", summary: "x"
      ).call
    }.to raise_error(RuntimeError, "boom")

    expect(Organization.where(name: "Rollback Org", sway_locale: bill.sway_locale).count).to eq(0)
    expect(OrganizationBillPosition.count).to eq(0)
  end

  # @lat: [[explanation/llm-summaries#Whose words a stored summary records]]
  describe "ai_summary provenance" do
    it "records the model's words when a draft is approved unchanged" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill, draft_org_positions: [
        {"org_name" => "ACME", "stance" => "support", "summary" => "The model wrote this."}
      ])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "The model wrote this.",
        index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:approved)
      position = OrganizationBillPosition.find_by(bill: bill) #: OrganizationBillPosition
      expect(position.ai_summary).to eq("The model wrote this.")
      expect(position.summary_ai_unreviewed?).to be(true)
    end

    # The operator rewrote the sentence in the browser and sent the new one.
    # The stored draft still holds the model's, so the two disagree.
    it "records nothing when the operator sends different words than the draft holds" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill, draft_org_positions: [
        {"org_name" => "ACME", "stance" => "support", "summary" => "The model wrote this."}
      ])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "A person rewrote this.",
        index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:approved)
      position = OrganizationBillPosition.find_by(bill: bill) #: OrganizationBillPosition
      expect(position.ai_summary).to be_nil
      expect(position.summary_ai_unreviewed?).to be(false)
    end

    # The operator saved the rewrite through the edit endpoint first, so the
    # stored draft IS their words and matches what Approve sends. Only the
    # mark can tell this apart from an untouched draft.
    it "records nothing for a draft a person edited through the edit endpoint" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill, draft_org_positions: [
        {"org_name" => "ACME", "stance" => "support", "summary" => "A person rewrote this.",
         BillLlmProvisioning::DRAFT_SUMMARY_EDITED_KEY => "2026-08-01T00:00:00Z"}
      ])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "A person rewrote this.",
        index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:approved)
      position = OrganizationBillPosition.find_by(bill: bill) #: OrganizationBillPosition
      expect(position.ai_summary).to be_nil
      expect(position.summary_ai_unreviewed?).to be(false)
    end

    it "records nothing for a caller that names no draft at all" do
      bill = create(:bill)

      described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Typed In By An Admin", support: "support", summary: "An admin wrote this."
      ).call

      position = OrganizationBillPosition.find_by(bill: bill) #: OrganizationBillPosition
      expect(position.ai_summary).to be_nil
      expect(position.summary_ai_unreviewed?).to be(false)
    end

    # A row first published from a draft and later re-approved from a person's
    # own words must stop claiming a model wrote it.
    it "clears a stale ai_summary when the same position is re-approved by hand" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill, draft_org_positions: [
        {"org_name" => "ACME", "stance" => "support", "summary" => "The model wrote this."}
      ])
      actor = create(:user)
      described_class.new(
        bill: bill, actor: actor,
        org_name: "ACME", support: "support", summary: "The model wrote this.",
        index: "0", draft_org_name: "ACME"
      ).call

      described_class.new(
        bill: bill, actor: actor,
        org_name: "ACME", support: "support", summary: "An admin rewrote this."
      ).call

      position = OrganizationBillPosition.find_by(bill: bill) #: OrganizationBillPosition
      expect(position.summary).to eq("An admin rewrote this.")
      expect(position.ai_summary).to be_nil
      expect(position.summary_ai_unreviewed?).to be(false)
    end
  end

  # The fifth refusal. A backstop, not the
  # primary guarantee — BillPositionsPromptBuilder already keeps a person
  # speaking for themselves from being offered to the model as a nameable
  # source, so this exists for the card an operator can still retype before
  # Approve, naming a name straight out of a resident's own signed letter.
  describe "the private-individual guard" do
    def cleaned_testimony_naming(name)
      text = "From: resident@gmail.com\nI support this bill.\n\n#{name}\n100 Example Street\nBaltimore, MD 21201\n"
      {
        "version" => 1,
        "text" => text,
        "counts" => {},
        "letters" => [
          {
            "position" => 0, "character_offset" => 0, "characters" => text.length,
            "sender_address" => "resident@gmail.com", "sender_domain" => "gmail.com",
            "source_kind" => "person_speaking_for_self", "source_evidence" => nil
          }
        ]
      }
    end

    # @lat: [[private-individual-guard-regions]]
    def long_testimony_letter(from:, mid_body_name:, signer:)
      <<~TEXT
        From: #{from}
        Sent: Wednesday, June 25, 2026 9:20 AM
        To: City Council <citycouncil@baltimorecity.gov>
        Subject: Testimony on the proposed development at Fell Point

        Dear Council Members,

        I am writing to oppose this bill because it changes the zoning along a
        residential block where families have lived for decades without being asked
        what they think about the change, and the traffic study behind it undercounts
        how many trucks already use this street every single day of the week. I oppose
        the #{mid_body_name}'s plan for this site, and I ask the
        council to table this bill until an independent study is completed by someone
        who does not already work for the agency proposing the change.

        #{signer}
        100 Example Street
        Baltimore, MD 21201
      TEXT
    end

    def cleaned_testimony_with_letter(text)
      {
        "version" => 1,
        "text" => text,
        "counts" => {},
        "letters" => [
          {
            "position" => 0, "character_offset" => 0, "characters" => text.length,
            "sender_address" => "resident@gmail.com", "sender_domain" => "gmail.com",
            "source_kind" => "person_speaking_for_self", "source_evidence" => nil
          }
        ]
      }
    end

    it "refuses a draft whose letter was read as a person speaking for themselves, and creates no organization row" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony submitted at the hearing on this bill.",
        cleaned_testimony: cleaned_testimony_naming("Alex Example"),
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
        draft_org_positions: [{"org_name" => "Alex Example", "stance" => "support", "summary" => "Supports the bill."}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Alex Example", support: "support", summary: "Supports the bill.",
        index: "0", draft_org_name: "Alex Example"
      ).call

      expect(outcome).to eq(:private_individual)
      expect(Organization.where(name: "Alex Example").count).to eq(0)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      # Nothing was destroyed either — the draft stays for the operator to see.
      expect(bill.bill_llm_provisioning.reload.draft_org_positions.length).to eq(1)
    end

    it "still approves a draft naming an organization the testimony read as a named organization" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony submitted at the hearing on this bill.",
        cleaned_testimony: cleaned_testimony_naming("Alex Example").merge(
          "letters" => [
            {
              "position" => 0, "character_offset" => 0, "characters" => 10,
              "sender_address" => "info@coalition.org", "sender_domain" => "coalition.org",
              "source_kind" => "named_organization", "source_evidence" => nil
            }
          ]
        ),
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
        draft_org_positions: [{"org_name" => "Housing Coalition", "stance" => "support", "summary" => "Backs it."}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Housing Coalition", support: "support", summary: "Backs it.",
        index: "0", draft_org_name: "Housing Coalition"
      ).call

      expect(outcome).to eq(:approved)
      expect(Organization.where(name: "Housing Coalition").count).to eq(1)
    end

    # WR-04. A plain substring test with no word boundary refuses an
    # organization whose name happens to appear inside an ordinary word, and
    # a short generic name ("Union", "CASA") appears inside many residents'
    # letters — the refusal is permanent and the operator cannot override it
    # from the screen.
    it "does not refuse an organization whose name only appears inside a longer word" do
      bill = create(:bill)
      text = "From: resident@gmail.com\nI support this bill because the tenants unionized last year.\n"
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony submitted at the hearing on this bill.",
        cleaned_testimony: cleaned_testimony_naming("Alex Example").merge(
          "text" => text,
          "letters" => [
            {"position" => 0, "character_offset" => 0, "characters" => text.length,
             "sender_address" => "resident@gmail.com", "sender_domain" => "gmail.com",
             "source_kind" => "person_speaking_for_self", "source_evidence" => nil}
          ]
        ),
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
        draft_org_positions: [{"org_name" => "Tenants Union", "stance" => "support", "summary" => "Backs it."}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Tenants Union", support: "support", summary: "Backs it.",
        index: "0", draft_org_name: "Tenants Union"
      ).call

      expect(outcome).to eq(:approved)
    end

    it "does not refuse on a name too short to be anyone's own name" do
      bill = create(:bill)
      text = "From: resident@gmail.com\nMy union local meets on Tuesdays and we discussed this bill.\n"
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony submitted at the hearing on this bill.",
        cleaned_testimony: cleaned_testimony_naming("Alex Example").merge(
          "text" => text,
          "letters" => [
            {"position" => 0, "character_offset" => 0, "characters" => text.length,
             "sender_address" => "resident@gmail.com", "sender_domain" => "gmail.com",
             "source_kind" => "person_speaking_for_self", "source_evidence" => nil}
          ]
        ),
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
        draft_org_positions: [{"org_name" => "Union", "stance" => "support", "summary" => "Backs it."}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Union", support: "support", summary: "Backs it.",
        index: "0", draft_org_name: "Union"
      ).call

      expect(outcome).to eq(:approved)
    end

    # @lat: [[testimony-attachment-rules#Every fixed phrase matches through the extracted-text helper]]
    it "still refuses when the name in the letter carries the line break extracted text puts there" do
      bill = create(:bill)
      text = "From: resident@gmail.com\nI support this bill.\n\nAlex \nExample\n100 Example Street\n"
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony submitted at the hearing on this bill.",
        cleaned_testimony: cleaned_testimony_naming("Alex Example").merge(
          "text" => text,
          "letters" => [
            {"position" => 0, "character_offset" => 0, "characters" => text.length,
             "sender_address" => "resident@gmail.com", "sender_domain" => "gmail.com",
             "source_kind" => "person_speaking_for_self", "source_evidence" => nil}
          ]
        ),
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
        draft_org_positions: [{"org_name" => "Alex Example", "stance" => "support", "summary" => "Supports the bill."}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Alex Example", support: "support", summary: "Supports the bill.",
        index: "0", draft_org_name: "Alex Example"
      ).call

      expect(outcome).to eq(:private_individual)
      expect(Organization.where(name: "Alex Example").count).to eq(0)
    end

    it "does not refuse a caller that names no draft at all" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony submitted at the hearing on this bill.",
        cleaned_testimony: cleaned_testimony_naming("Alex Example"),
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago)

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Alex Example", support: "support", summary: "An admin's own words."
      ).call

      expect(outcome).to eq(:approved)
    end

    # The pre-transaction check is only an optimisation; a concurrent write
    # landing the individual mark in that window must still roll back — the
    # same shape the D-CR-01 "shrinks after the pre-check" example above
    # proves for the identity guard, reused here for the fifth refusal.
    it "reaches the refusal on the second check, under the write lock, when the mark lands after the pre-check ran" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"org_name" => "Alex Example", "stance" => "support", "summary" => "Supports the bill."}])

      service = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Alex Example", support: "support", summary: "Supports the bill.",
        index: "0", draft_org_name: "Alex Example"
      )
      allow(service).to receive(:run_in_flight?).and_wrap_original do |original, provisioning_row = nil|
        result = original.call(provisioning_row)
        BillLlmProvisioning.find(provisioning.id).update!(
          cleaned_testimony: cleaned_testimony_naming("Alex Example"),
          cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago
        )
        result
      end

      outcome = service.call

      expect(outcome).to eq(:private_individual)
      expect(Organization.where(name: "Alex Example").count).to eq(0)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
    end

    # @lat: [[private-individual-guard-regions]]
    it "approves an organization named only in the body prose of a resident's letter" do
      bill = create(:bill)
      text = long_testimony_letter(
        from: "resident@gmail.com",
        mid_body_name: "Baltimore Development Corporation",
        signer: "Jordan Ellery"
      )
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony submitted at the hearing on this bill.",
        cleaned_testimony: cleaned_testimony_with_letter(text),
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
        draft_org_positions: [{"org_name" => "Baltimore Development Corporation", "stance" => "oppose", "summary" => "Opposes the plan."}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Baltimore Development Corporation", support: "oppose", summary: "Opposes the plan.",
        index: "0", draft_org_name: "Baltimore Development Corporation"
      ).call

      expect(outcome).to eq(:approved)
      expect(Organization.where(name: "Baltimore Development Corporation").count).to eq(1)
    end

    it "still refuses a person's own name found in the letter's signature region" do
      bill = create(:bill)
      text = long_testimony_letter(
        from: "resident@gmail.com",
        mid_body_name: "Baltimore Development Corporation",
        signer: "Jordan Ellery"
      )
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony submitted at the hearing on this bill.",
        cleaned_testimony: cleaned_testimony_with_letter(text),
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
        draft_org_positions: [{"org_name" => "Jordan Ellery", "stance" => "oppose", "summary" => "Opposes the plan."}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Jordan Ellery", support: "oppose", summary: "Opposes the plan.",
        index: "0", draft_org_name: "Jordan Ellery"
      ).call

      expect(outcome).to eq(:private_individual)
      expect(Organization.where(name: "Jordan Ellery").count).to eq(0)
    end

    it "still refuses a person's own name found in the letter's From: header region" do
      bill = create(:bill)
      text = long_testimony_letter(
        from: "Alex Example <alexexample@gmail.com>",
        mid_body_name: "Baltimore Development Corporation",
        signer: "Priya Okonkwo"
      )
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony submitted at the hearing on this bill.",
        cleaned_testimony: cleaned_testimony_with_letter(text),
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
        draft_org_positions: [{"org_name" => "Alex Example", "stance" => "oppose", "summary" => "Opposes the plan."}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Alex Example", support: "oppose", summary: "Opposes the plan.",
        index: "0", draft_org_name: "Alex Example"
      ).call

      expect(outcome).to eq(:private_individual)
      expect(Organization.where(name: "Alex Example").count).to eq(0)
    end

    it "reaches the refusal on the second check when the match is confined to the signature region" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"org_name" => "Jordan Ellery", "stance" => "oppose", "summary" => "Opposes the plan."}])
      text = long_testimony_letter(
        from: "resident@gmail.com",
        mid_body_name: "Baltimore Development Corporation",
        signer: "Jordan Ellery"
      )

      service = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Jordan Ellery", support: "oppose", summary: "Opposes the plan.",
        index: "0", draft_org_name: "Jordan Ellery"
      )
      allow(service).to receive(:run_in_flight?).and_wrap_original do |original, provisioning_row = nil|
        result = original.call(provisioning_row)
        BillLlmProvisioning.find(provisioning.id).update!(
          cleaned_testimony: cleaned_testimony_with_letter(text),
          cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago
        )
        result
      end

      outcome = service.call

      expect(outcome).to eq(:private_individual)
      expect(Organization.where(name: "Jordan Ellery").count).to eq(0)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
    end

    # @lat: [[private-individual-guard-regions#Direct organization evidence stands the guard down]]
    describe "direct organization evidence" do
      def cleaned_testimony_with_letters(texts, kinds:)
        full_text = +""
        letters = texts.each_with_index.map do |text, i|
          letter = {
            "position" => i, "character_offset" => full_text.length, "characters" => text.length,
            "sender_address" => "sender#{i}@example.com", "sender_domain" => "example.com",
            "source_kind" => kinds.fetch(i), "source_evidence" => nil
          }
          full_text << text
          letter
        end
        {"version" => 1, "text" => full_text, "counts" => {}, "letters" => letters}
      end

      it "stands down when a public_body letter names the agency deep in its own body, past both region bounds" do
        bill = create(:bill)
        resident_text = "From: resident@gmail.com\nI support this bill.\n\nBaltimore Housing Department\n100 Example Street\nBaltimore, MD 21201\n"
        padding = "Filler sentence about the hearing schedule and nothing else. " * 10
        agency_text = "From: clerk@baltimorehousing.gov\nSubject: Testimony\n\n#{padding}\nOn behalf of the Baltimore Housing Department, we support this bill.\n#{padding}\nRegards,\nThe Clerk's Office\n"
        create(:bill_llm_provisioning, bill: bill,
          extracted_testimony: "Testimony submitted at the hearing on this bill.",
          cleaned_testimony: cleaned_testimony_with_letters(
            [resident_text, agency_text], kinds: %w[person_speaking_for_self public_body]
          ),
          cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
          draft_org_positions: [{"org_name" => "Baltimore Housing Department", "stance" => "support", "summary" => "Supports the bill."}])

        outcome = described_class.new(
          bill: bill, actor: create(:user),
          org_name: "Baltimore Housing Department", support: "support", summary: "Supports the bill.",
          index: "0", draft_org_name: "Baltimore Housing Department"
        ).call

        expect(outcome).to eq(:approved)
        expect(Organization.where(name: "Baltimore Housing Department").count).to eq(1)
      end

      it "stands down when a named_organization letter names the org in the phrase that classified it" do
        bill = create(:bill)
        resident_text = "From: resident@gmail.com\nI support this bill.\n\nHousing Coalition\n100 Example Street\nBaltimore, MD 21201\n"
        org_text = "From: info@coalition.org\nOn behalf of the Housing Coalition, we back this bill.\n"
        create(:bill_llm_provisioning, bill: bill,
          extracted_testimony: "Testimony submitted at the hearing on this bill.",
          cleaned_testimony: cleaned_testimony_with_letters(
            [resident_text, org_text], kinds: %w[person_speaking_for_self named_organization]
          ),
          cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
          draft_org_positions: [{"org_name" => "Housing Coalition", "stance" => "support", "summary" => "Backs it."}])

        outcome = described_class.new(
          bill: bill, actor: create(:user),
          org_name: "Housing Coalition", support: "support", summary: "Backs it.",
          index: "0", draft_org_name: "Housing Coalition"
        ).call

        expect(outcome).to eq(:approved)
        expect(Organization.where(name: "Housing Coalition").count).to eq(1)
      end

      # @lat: [[private-individual-guard-regions#Only where the letter identifies itself]]
      it "still refuses when an organization letter only mentions the resident's name in passing" do
        bill = create(:bill)
        resident_text = "From: resident@gmail.com\nI support this bill.\n\nAlex Example\n100 Example Street\nBaltimore, MD 21201\n"
        padding = "Filler sentence about the hearing schedule and nothing else. " * 10
        agency_text = "From: clerk@dpw.baltimorecity.gov\nOn behalf of the Department of Public Works, we support this bill.\n#{padding}\nWe thank Councilman Alex Example for his attention to this matter.\n#{padding}\nRegards,\nThe Clerk's Office\n"
        create(:bill_llm_provisioning, bill: bill,
          extracted_testimony: "Testimony submitted at the hearing on this bill.",
          cleaned_testimony: cleaned_testimony_with_letters(
            [resident_text, agency_text], kinds: %w[person_speaking_for_self public_body]
          ),
          cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
          draft_org_positions: [{"org_name" => "Alex Example", "stance" => "support", "summary" => "Supports the bill."}])

        outcome = described_class.new(
          bill: bill, actor: create(:user),
          org_name: "Alex Example", support: "support", summary: "Supports the bill.",
          index: "0", draft_org_name: "Alex Example"
        ).call

        expect(outcome).to eq(:private_individual)
        expect(Organization.where(name: "Alex Example").count).to eq(0)
      end

      it "still refuses when the bill's organization-evidence letter names a different organization" do
        bill = create(:bill)
        resident_text = "From: resident@gmail.com\nI support this bill.\n\nAlex Example\n100 Example Street\nBaltimore, MD 21201\n"
        agency_text = "From: clerk@dpw.baltimorecity.gov\nOn behalf of the Department of Public Works, we support this bill.\n"
        create(:bill_llm_provisioning, bill: bill,
          extracted_testimony: "Testimony submitted at the hearing on this bill.",
          cleaned_testimony: cleaned_testimony_with_letters(
            [resident_text, agency_text], kinds: %w[person_speaking_for_self public_body]
          ),
          cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
          draft_org_positions: [{"org_name" => "Alex Example", "stance" => "support", "summary" => "Supports the bill."}])

        outcome = described_class.new(
          bill: bill, actor: create(:user),
          org_name: "Alex Example", support: "support", summary: "Supports the bill.",
          index: "0", draft_org_name: "Alex Example"
        ).call

        expect(outcome).to eq(:private_individual)
        expect(Organization.where(name: "Alex Example").count).to eq(0)
      end
    end

    # @lat: [[private-individual-guard-override]]
    describe "the operator override" do
      it "approves when the operator confirms past the refusal, and records the override in the activity log" do
        bill = create(:bill)
        create(:bill_llm_provisioning, bill: bill,
          extracted_testimony: "Testimony submitted at the hearing on this bill.",
          cleaned_testimony: cleaned_testimony_naming("Alex Example"),
          cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
          draft_org_positions: [{"org_name" => "Alex Example", "stance" => "support", "summary" => "Supports the bill."}])

        outcome = described_class.new(
          bill: bill, actor: create(:user),
          org_name: "Alex Example", support: "support", summary: "Supports the bill.",
          index: "0", draft_org_name: "Alex Example", override_private_individual: true
        ).call

        expect(outcome).to eq(:approved)
        expect(Organization.where(name: "Alex Example").count).to eq(1)
        entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").order(:id).last
        expect(entry.payload["private_individual_override"]).to eq(true)
      end

      it "does not record the override when the flag rode along on an approval the guard was never going to refuse" do
        bill = create(:bill)
        create(:bill_llm_provisioning, :with_testimony, bill: bill,
          draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])

        outcome = described_class.new(
          bill: bill, actor: create(:user),
          org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME",
          override_private_individual: true
        ).call

        expect(outcome).to eq(:approved)
        entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").order(:id).last
        expect(entry.payload).not_to have_key("private_individual_override")
      end

      it "approves via the in-transaction re-check when the refusing mark lands after the pre-check ran" do
        bill = create(:bill)
        provisioning = create(:bill_llm_provisioning, :with_testimony, bill: bill,
          draft_org_positions: [{"org_name" => "Alex Example", "stance" => "support", "summary" => "Supports the bill."}])

        service = described_class.new(
          bill: bill, actor: create(:user),
          org_name: "Alex Example", support: "support", summary: "Supports the bill.",
          index: "0", draft_org_name: "Alex Example", override_private_individual: true
        )
        allow(service).to receive(:run_in_flight?).and_wrap_original do |original, provisioning_row = nil|
          result = original.call(provisioning_row)
          BillLlmProvisioning.find(provisioning.id).update!(
            cleaned_testimony: cleaned_testimony_naming("Alex Example"),
            cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago
          )
          result
        end

        outcome = service.call

        expect(outcome).to eq(:approved)
        expect(Organization.where(name: "Alex Example").count).to eq(1)
      end

      it "still refuses on a different in-transaction re-check even with the override flag set" do
        bill = create(:bill)
        drafts = [
          {"org_name" => "ACME", "stance" => "support", "summary" => "Backs it.",
           BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY => "2026-07-01T00:00:00Z"}
        ]
        create(:bill_llm_provisioning, :with_testimony, bill: bill, draft_org_positions: drafts)

        outcome = described_class.new(
          bill: bill, actor: create(:user),
          org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME",
          override_private_individual: true
        ).call

        expect(outcome).to eq(:evidence_retracted)
        expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
        expect(Organization.where(name: "ACME").count).to eq(0)
      end
    end
  end

  # #run_in_flight? used to check only
  # provisioning.pending?/generating? — the LLM SUMMARY job's own state, not
  # Testimony::CleanAndGroupService's. A clean-testimony run rewrites this
  # bill's cleaned artifact (the drafts and letters Approve reads) out from
  # under an in-flight approval just as surely as a second summary run would.
  describe "the run-in-flight guard also watches clean-testimony (B7)" do
    def testimony_sourced_draft_bill
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill,
        draft_org_positions: [{"org_name" => "ACME", "stance" => "support", "summary" => "Backs it."}])
      bill
    end

    it "returns :run_in_flight while a clean-testimony run is going for THIS bill, even though the summary is idle" do
      bill = testimony_sourced_draft_bill
      create(:legislation_pipeline_run, status: "cleaning_testimony", bill: bill)

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:run_in_flight)
      expect(Organization.where(name: "ACME").count).to eq(0)
    end

    it "returns :run_in_flight during a global all-bills clean-testimony run, not only a single-bill one" do
      bill = testimony_sourced_draft_bill
      create(:legislation_pipeline_run, status: "cleaning_testimony", bill: nil)

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:run_in_flight)
      expect(Organization.where(name: "ACME").count).to eq(0)
    end

    it "does not refuse on a clean-testimony run for a DIFFERENT bill" do
      bill = testimony_sourced_draft_bill
      create(:legislation_pipeline_run, status: "cleaning_testimony", bill: create(:bill))

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:approved)
    end

    it "does not refuse on a run for this bill sitting at some other stage, not cleaning_testimony" do
      bill = testimony_sourced_draft_bill
      create(:legislation_pipeline_run, status: "extracting_text", bill: bill)

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "ACME", support: "support", summary: "Backs it.", index: "0", draft_org_name: "ACME"
      ).call

      expect(outcome).to eq(:approved)
    end
  end

  # The sixth refusal. The client's own
  # approveDisabled guard is the fast path; this is the gate a stale tab
  # cannot skip past.
  describe "the coverage acknowledgement guard" do
    before do
      allow(Testimony::CoverageReport).to receive(:coverage_gap?).and_call_original
    end

    it "refuses a draft on a bill whose testimony was left out and not acknowledged, and creates no organization row" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "R" * (max_chars + 500),
        draft_org_positions: [{"org_name" => "Housing Coalition", "stance" => "support", "summary" => "Backs it."}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Housing Coalition", support: "support", summary: "Backs it.",
        index: "0", draft_org_name: "Housing Coalition"
      ).call

      expect(outcome).to eq(:coverage_not_acknowledged)
      expect(Organization.where(name: "Housing Coalition").count).to eq(0)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
    end

    it "approves once the coverage has been acknowledged" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "R" * (max_chars + 500),
        draft_org_positions: [{"org_name" => "Housing Coalition", "stance" => "support", "summary" => "Backs it."}])
      digest = Testimony::CoverageReport.call(bill: bill).digest
      create(:testimony_coverage_acknowledgement, bill: bill, coverage_digest: digest)

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Housing Coalition", support: "support", summary: "Backs it.",
        index: "0", draft_org_name: "Housing Coalition"
      ).call

      expect(outcome).to eq(:approved)
    end

    it "does not refuse a caller that names no draft at all" do
      bill = create(:bill)
      create(:bill_llm_provisioning, bill: bill, extracted_testimony: "R" * (max_chars + 500))

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Direct Org", support: "support", summary: "An admin's own words."
      ).call

      expect(outcome).to eq(:approved)
    end

    # The pre-transaction check is only an optimisation; a concurrent write
    # landing a fresh, unacknowledged artifact in that window must still roll
    # back — the same shape the private-individual guard's own "reaches the
    # refusal on the second check" example proves above, reused here for the
    # sixth refusal. @bill's cached bill_llm_provisioning association is what
    # keeps the pre-check stale until with_lock reloads it, exactly like the
    # private-individual case this technique is borrowed from.
    it "reaches the refusal on the second check, under the write lock, when the acknowledgement stops matching after the pre-check ran" do
      bill = create(:bill)
      provisioning = create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "R" * (max_chars + 500),
        draft_org_positions: [{"org_name" => "Housing Coalition", "stance" => "support", "summary" => "Backs it."}])
      digest = Testimony::CoverageReport.call(bill: bill).digest
      create(:testimony_coverage_acknowledgement, bill: bill, coverage_digest: digest)

      service = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Housing Coalition", support: "support", summary: "Backs it.",
        index: "0", draft_org_name: "Housing Coalition"
      )
      allow(service).to receive(:draft_names_private_individual?).and_wrap_original do |original, provisioning_row = nil|
        result = original.call(provisioning_row)
        BillLlmProvisioning.find(provisioning.id).update!(extracted_testimony: "R" * (max_chars + 9_000))
        result
      end

      outcome = service.call

      expect(outcome).to eq(:coverage_not_acknowledged)
      expect(Organization.where(name: "Housing Coalition").count).to eq(0)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
    end
  end

  describe "approving news-sourced draft organization positions" do
    let(:sway_locale) { create(:sway_locale) }
    let(:bill) { create(:bill, sway_locale: sway_locale) }
    let(:actor) { create(:user) }
    let(:news_article) { create(:news_article, article_kind: "reporting") }
    let(:bna) do
      b = create(
        :bill_news_article,
        bill: bill,
        news_article: news_article,
        approved: true,
        approved_by: actor,
        approved_at: Time.current
      )
      b.update_columns(current_text_version_id: text_version.id)
      b
    end
    let(:article_text) do
      "\"We strongly support this legislation to safeguard fair housing for all tenants,\" " \
        "said Jane Doe, Executive Director of Baltimore Tenants Union."
    end
    let(:text_version) do
      create(
        :news_article_text_version,
        news_article: news_article,
        extraction_status: "extracted",
        text: article_text
      )
    end
    let(:excerpt) { "We strongly support this legislation to safeguard fair housing for all tenants" }
    let(:news_draft) do
      {
        "org_name" => "Baltimore Tenants Union",
        "stance" => "support",
        "summary" => "Supports fair housing legislation for tenants.",
        "bill_news_article_id" => bna.id,
        "text_version_id" => text_version.id,
        "evidence_excerpt" => excerpt,
        "speaker_name" => "Jane Doe",
        "speaker_role" => "Executive Director",
        "source_url" => "https://example.com/article",
        "outlet_name" => "The Baltimore Banner",
        "article_title" => "Tenants Fight for Fair Housing",
        "excerpt_offset" => 1,
        "excerpt_length" => excerpt.length,
        "excerpt_paragraph" => 1,
        "excerpt_page" => 1
      }
    end

    it "approves a news-sourced draft position when bill has no hearing testimony" do
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [news_draft])

      outcome = described_class.new(
        bill: bill,
        actor: actor,
        org_name: "Baltimore Tenants Union",
        support: "support",
        summary: "Supports fair housing legislation for tenants.",
        index: "0",
        draft_org_name: "Baltimore Tenants Union"
      ).call

      expect(outcome).to eq(:approved)
      org = Organization.find_by(name: "Baltimore Tenants Union", sway_locale: sway_locale)
      expect(org).to be_present
      position = OrganizationBillPosition.find_by(bill: bill, organization: org)
      expect(position).to be_present
      expect(position&.support).to eq("FOR")
      expect(position&.active).to be(true)
      expect(position&.ai_summary).to be_nil
      expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq([])
    end

    it "records the position as compiled from a news article, with the draft's source URL" do
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [news_draft])

      described_class.new(
        bill: bill, actor: actor, org_name: "Baltimore Tenants Union", support: "support",
        summary: "Supports fair housing legislation for tenants.", index: "0",
        draft_org_name: "Baltimore Tenants Union"
      ).call

      position = OrganizationBillPosition.find_by!(bill: bill)
      expect(position.source_kind).to eq("news_article")
      expect(position.source_url).to eq("https://example.com/article")
    end

    it "refuses approval with :organization_has_users when matched organization has user memberships" do
      org = create(:organization, name: "Baltimore Tenants Union", sway_locale: sway_locale)
      create(:user_organization_membership, organization: org, user: actor)
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [news_draft])

      outcome = described_class.new(
        bill: bill,
        actor: actor,
        org_name: "Baltimore Tenants Union",
        support: "support",
        summary: "Supports fair housing legislation for tenants.",
        index: "0",
        draft_org_name: "Baltimore Tenants Union"
      ).call

      expect(outcome).to eq(:organization_has_users)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
      expect(bill.bill_llm_provisioning.reload.draft_org_positions.length).to eq(1)
    end

    it "refuses approval with :evidence_retracted when backing article is unapproved" do
      bna.update_columns(approved: false)
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [news_draft])

      outcome = described_class.new(
        bill: bill,
        actor: actor,
        org_name: "Baltimore Tenants Union",
        support: "support",
        summary: "Supports fair housing legislation for tenants.",
        index: "0",
        draft_org_name: "Baltimore Tenants Union"
      ).call

      expect(outcome).to eq(:evidence_retracted)
      expect(OrganizationBillPosition.where(bill: bill).count).to eq(0)
    end

    it "refuses approval with :evidence_retracted when text_version_id changed on article" do
      other_tv = create(
        :news_article_text_version,
        news_article: news_article,
        extraction_status: "extracted",
        text: "Different version text."
      )
      bna.update_columns(current_text_version_id: other_tv.id)
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [news_draft])

      outcome = described_class.new(
        bill: bill,
        actor: actor,
        org_name: "Baltimore Tenants Union",
        support: "support",
        summary: "Supports fair housing legislation for tenants.",
        index: "0",
        draft_org_name: "Baltimore Tenants Union"
      ).call

      expect(outcome).to eq(:evidence_retracted)
    end

    it "refuses approval with :evidence_retracted when draft carries evidence_retracted_at timestamp" do
      retracted_draft = news_draft.merge("evidence_retracted_at" => Time.current.iso8601)
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [retracted_draft])

      outcome = described_class.new(
        bill: bill,
        actor: actor,
        org_name: "Baltimore Tenants Union",
        support: "support",
        summary: "Supports fair housing legislation for tenants.",
        index: "0",
        draft_org_name: "Baltimore Tenants Union"
      ).call

      expect(outcome).to eq(:evidence_retracted)
    end

    it "bypasses private individual letter checks on news-sourced drafts" do
      provisioning = create(:bill_llm_provisioning, bill: bill, draft_org_positions: [news_draft])
      full_text = "My name is Baltimore Tenants Union and I write as a resident."
      provisioning.update!(
        cleaned_testimony: {
          "text" => full_text,
          "letters" => [
            {
              "character_offset" => 0,
              "characters" => full_text.length,
              "source_kind" => "person_speaking_for_self",
              "position" => 1
            }
          ]
        }
      )

      outcome = described_class.new(
        bill: bill,
        actor: actor,
        org_name: "Baltimore Tenants Union",
        support: "support",
        summary: "Supports fair housing legislation for tenants.",
        index: "0",
        draft_org_name: "Baltimore Tenants Union"
      ).call

      expect(outcome).to eq(:approved)
    end

    it "bypasses coverage unacknowledged checks on news-sourced drafts" do
      allow(Testimony::CoverageReport).to receive(:coverage_gap?).and_return(true)
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [news_draft])

      outcome = described_class.new(
        bill: bill,
        actor: actor,
        org_name: "Baltimore Tenants Union",
        support: "support",
        summary: "Supports fair housing legislation for tenants.",
        index: "0",
        draft_org_name: "Baltimore Tenants Union"
      ).call

      expect(outcome).to eq(:approved)
    end

    it "reuses existing organization matched by normalized suffix without creating duplicate" do
      existing_org = create(:organization, name: "Baltimore Tenants Union", sway_locale: sway_locale)
      draft_with_suffix = news_draft.merge("org_name" => "Baltimore Tenants Union, Inc.")
      create(:bill_llm_provisioning, bill: bill, draft_org_positions: [draft_with_suffix])

      expect {
        described_class.new(
          bill: bill,
          actor: actor,
          org_name: "Baltimore Tenants Union, Inc.",
          support: "support",
          summary: "Supports fair housing legislation for tenants.",
          index: "0",
          draft_org_name: "Baltimore Tenants Union, Inc."
        ).call
      }.not_to change(Organization, :count)

      position = OrganizationBillPosition.find_by(bill: bill, organization: existing_org)
      expect(position).to be_present
    end

    it "approves a news-sourced draft edited to neutral stance with nil summary on a bill without hearing testimony" do
      neutral_news_draft = news_draft.merge("stance" => "neutral", "summary" => nil)
      create(
        :bill_llm_provisioning,
        bill: bill,
        extracted_testimony: nil,
        supplemental_testimony: nil,
        draft_org_positions: [neutral_news_draft]
      )

      outcome = described_class.new(
        bill: bill,
        actor: actor,
        org_name: "Baltimore Tenants Union",
        support: "neutral",
        summary: "",
        index: "0",
        draft_org_name: "Baltimore Tenants Union"
      ).call

      expect(outcome).to eq(:approved)
      org = Organization.find_by(name: "Baltimore Tenants Union", sway_locale: sway_locale)
      expect(org).to be_present
      position = OrganizationBillPosition.find_by(bill: bill, organization: org)
      expect(position).to be_present
      expect(position&.support).to eq("ABSTAIN")
      expect(position&.neutral?).to be(true)
      expect(position&.summary).to eq(OrganizationBillPosition::DEFAULT_SUMMARY)
      expect(position&.summary_for_readers).to be_nil
      expect(position&.ai_summary).to be_nil
      expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq([])
    end
  end

  describe "recording where the position came from" do
    it "records a testimony draft as hearing testimony with no URL" do
      bill = create(:bill)
      create(:bill_llm_provisioning, :with_testimony, bill: bill, draft_org_positions: [{"org_name" => "First"}])

      outcome = described_class.new(
        bill: bill, actor: create(:user),
        org_name: "First", support: "support", summary: "x", index: "0", draft_org_name: "First"
      ).call

      expect(outcome).to eq(:approved)
      position = OrganizationBillPosition.find_by!(bill: bill)
      expect(position.source_kind).to eq("hearing_testimony")
      expect(position.source_url).to be_nil
    end

    it "records a claimed affiliation from a testimony letter as hearing testimony with no URL" do
      bill = create(:bill)
      body = "I write on behalf of the Waverly Tenants Alliance."
      create(:bill_llm_provisioning, :with_testimony, bill: bill, cleaned_testimony: {
        "version" => 1,
        "text" => body,
        "letters" => [{"position" => 0, "character_offset" => 0, "characters" => body.length,
                       "source_kind" => "person_speaking_for_org"}]
      })

      outcome = described_class.new(
        bill: bill, actor: create(:user), org_name: "Waverly Tenants Alliance", support: "support",
        summary: "Backs the bill", claimed_affiliation_position: 0
      ).call

      expect(outcome).to eq(:approved)
      position = OrganizationBillPosition.find_by!(bill: bill)
      expect(position.source_kind).to eq("hearing_testimony")
      expect(position.source_url).to be_nil
    end

    it "records an approval that names no draft as a Sway admin entry with no URL" do
      bill = create(:bill)

      described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Brand New Org", support: "support", summary: "Backs the bill"
      ).call

      position = OrganizationBillPosition.find_by!(bill: bill)
      expect(position.source_kind).to eq("sway_admin")
      expect(position.source_url).to be_nil
    end

    it "replaces an earlier origin when Sway approves a new position for the same organization" do
      bill = create(:bill)
      organization = create(:organization, name: "Brand New Org", sway_locale: bill.sway_locale)
      create(:organization_bill_position, bill: bill, organization: organization,
        source_kind: "news_article", source_url: "https://example.com/old")

      described_class.new(
        bill: bill, actor: create(:user),
        org_name: "Brand New Org", support: "support", summary: "Backs the bill"
      ).call

      position = OrganizationBillPosition.find_by!(bill: bill)
      expect(position.source_kind).to eq("sway_admin")
      expect(position.source_url).to be_nil
    end
  end
end
