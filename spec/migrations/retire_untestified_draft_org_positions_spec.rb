# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260726000002_retire_untestified_draft_org_positions")

# @lat: [[retire-untestified-draft-org-positions-spec-design#The '""' vs '' SQL trap]]
RSpec.describe "RetireUntestifiedDraftOrgPositions data migration", type: :model do
  let(:migration) { RetireUntestifiedDraftOrgPositions.new }
  let(:bill) { create(:bill) }

  def drafts_for(provisioning)
    provisioning.reload.draft_org_positions
  end

  def retracted?(entry)
    BillLlmProvisioning.draft_evidence_retracted?(entry)
  end

  # @lat: [[retire-untestified-draft-org-positions-spec-design#Why "touches nothing" is checked against the write itself]]
  def update_statements
    statements = [] #: Array[String]
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      sql = payload[:sql].to_s
      statements << sql if sql.match?(/\AUPDATE\s+"bill_llm_provisionings"/i)
    end
    begin
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
    statements
  end

  let(:draft) do
    {"org_name" => "Fabricated Coalition", "stance" => "support", "summary" => "Derived from the diff."}
  end

  context "a bill with drafts and no testimony of any kind" do
    let!(:provisioning) do
      create(:bill_llm_provisioning, bill: bill,
        draft_org_positions: [draft],
        extracted_testimony: nil,
        supplemental_testimony: nil)
    end

    it "stamps the draft as evidence-retracted" do
      migration.up

      expect(retracted?(drafts_for(provisioning).first)).to be(true)
    end

    # Leaving the data in place matters: operators work through this array by
    # hand, and Reject and Edit still work on a draft that has been marked.
    it "destroys nothing" do
      migration.up

      entry = drafts_for(provisioning).first
      expect(entry["org_name"]).to eq("Fabricated Coalition")
      expect(entry["stance"]).to eq("support")
    end
  end

  # @lat: [[retire-untestified-draft-org-positions-spec-design#Why a row WITH testimony is left alone, and why that guard cannot be widened]]
  context "a bill whose drafts have testimony behind them" do
    it "leaves a draft alone when extracted_testimony is present" do
      provisioning = create(:bill_llm_provisioning, bill: bill,
        draft_org_positions: [draft],
        extracted_testimony: "ORG X supports the bill.")

      migration.up

      expect(retracted?(drafts_for(provisioning).first)).to be(false)
    end

    it "leaves a draft alone when only supplemental_testimony is present" do
      provisioning = create(:bill_llm_provisioning, bill: bill,
        draft_org_positions: [draft],
        extracted_testimony: nil,
        supplemental_testimony: "Operator-pasted testimony.")

      migration.up

      expect(retracted?(drafts_for(provisioning).first)).to be(false)
    end
  end

  # @lat: [[testimony-present-sql-ruby-predicate-mismatch#Not the same as the supplemental_testimony widening]]
  describe "the testimony question is asked with the one predicate (D-IN-03)" do
    it "stamps a row whose extracted_testimony is whitespace only" do
      provisioning = create(:bill_llm_provisioning, bill: bill,
        draft_org_positions: [draft],
        extracted_testimony: "   \n\t ",
        supplemental_testimony: nil)
      expect(provisioning.testimony_present?).to be(false)

      migration.up

      expect(retracted?(drafts_for(provisioning).first)).to be(true)
    end

    it "stamps a row whose supplemental_testimony is whitespace only" do
      provisioning = create(:bill_llm_provisioning, bill: bill,
        draft_org_positions: [draft],
        extracted_testimony: nil,
        supplemental_testimony: "  ")
      expect(provisioning.testimony_present?).to be(false)

      migration.up

      expect(retracted?(drafts_for(provisioning).first)).to be(true)
    end
  end

  # @lat: [[retire-untestified-draft-org-positions-spec-design#The '""' vs '' SQL trap]]
  describe ".untestified_draft_rows" do
    it "excludes an empty-array row in SQL, not only in Ruby" do
      create(:bill_llm_provisioning, bill: bill,
        draft_org_positions: [],
        extracted_testimony: nil,
        supplemental_testimony: nil)
      bearing = create(:bill_llm_provisioning, bill: create(:bill),
        draft_org_positions: [draft],
        extracted_testimony: nil,
        supplemental_testimony: nil)

      expect(RetireUntestifiedDraftOrgPositions.untestified_draft_rows.pluck(:id)).to eq([bearing.id])
    end

    # @lat: [[retire-untestified-draft-org-positions-spec-design#The '""' vs '' SQL trap]]
    it "compares against the serialized empty array, not a JSON-dumped string" do
      sql = RetireUntestifiedDraftOrgPositions.draft_bearing_rows.to_sql

      expect(sql).to include(%(!= '[]'))
      expect(sql).not_to include(%('"[]"'))
    end

    it "still excludes rows that carry testimony of either kind" do
      create(:bill_llm_provisioning, bill: bill,
        draft_org_positions: [draft],
        extracted_testimony: "ORG X supports the bill.")
      create(:bill_llm_provisioning, bill: create(:bill),
        draft_org_positions: [draft],
        extracted_testimony: nil,
        supplemental_testimony: "Operator-pasted testimony.")

      expect(RetireUntestifiedDraftOrgPositions.untestified_draft_rows).to be_empty
    end

    # The SQL half must select at least every row the final answer could need, or
    # moving the testimony question into Ruby would have put it out of reach. A
    # row the drafts half leaves out is never loaded, so it is never asked.
    it "carries every candidate through to the Ruby predicate" do
      testified = create(:bill_llm_provisioning, bill: bill,
        draft_org_positions: [draft],
        extracted_testimony: "   ")

      expect(RetireUntestifiedDraftOrgPositions.draft_bearing_rows.pluck(:id)).to include(testified.id)
      expect(RetireUntestifiedDraftOrgPositions.untestified_draft_rows.pluck(:id)).to eq([testified.id])
    end
  end

  it "is idempotent — a second run keeps the first timestamp" do
    provisioning = create(:bill_llm_provisioning, bill: bill,
      draft_org_positions: [draft],
      extracted_testimony: nil,
      supplemental_testimony: nil)

    migration.up
    first_stamp = drafts_for(provisioning).first[BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY]

    migration.up

    expect(drafts_for(provisioning).first[BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq(first_stamp)
  end

  # @lat: [[retire-untestified-draft-org-positions-spec-design#Why a retracted row keeps its original timestamp]]
  it "preserves a mark half (a) already wrote" do
    existing = 3.days.ago.iso8601
    provisioning = create(:bill_llm_provisioning, bill: bill,
      draft_org_positions: [draft.merge(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY => existing)],
      extracted_testimony: nil,
      supplemental_testimony: nil)

    migration.up

    expect(drafts_for(provisioning).first[BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY]).to eq(existing)
  end

  # @lat: [[retire-untestified-draft-org-positions-spec-design#Why the empty-""-string example replaced an earlier, blind one]]
  it "issues no write for a row the SQL admits but Ruby reads as holding no drafts" do
    provisioning = create(:bill_llm_provisioning, bill: bill,
      draft_org_positions: [draft],
      extracted_testimony: nil,
      supplemental_testimony: nil)
    ActiveRecord::Base.connection.execute(
      "UPDATE bill_llm_provisionings SET draft_org_positions = '' WHERE id = #{provisioning.id}"
    )

    expect(update_statements { migration.up }).to be_empty
  end

  # Kept, and renamed to say what it really shows: the SQL leaves out a row whose
  # array is empty, so the loop never sees it. That is the same claim
  # .untestified_draft_rows makes above, checked here through #up.
  it "issues no write on a bill whose drafts array is empty" do
    create(:bill_llm_provisioning, bill: bill,
      draft_org_positions: [],
      extracted_testimony: nil,
      supplemental_testimony: nil)

    expect(update_statements { migration.up }).to be_empty
  end

  # The same claim about a different row: one that is ALREADY fully stamped must
  # not be written again. The example above pins that a second run keeps the
  # first timestamp, which would still hold if the row were rewritten with the
  # same stamp. This one pins that no rewrite happens at all.
  it "issues no write on a row whose every draft is already stamped" do
    create(:bill_llm_provisioning, bill: bill,
      draft_org_positions: [draft.merge(BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY => 3.days.ago.iso8601)],
      extracted_testimony: nil,
      supplemental_testimony: nil)

    expect(update_statements { migration.up }).to be_empty
  end
end
