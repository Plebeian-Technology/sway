# frozen_string_literal: true

require "rails_helper"

# The Clear button behind PATCH
# /bills/:id/supplemental_testimony. Pins the boundary between write
# nothing and write: clearing a nonexistent column must leave the
# database untouched.
RSpec.describe UpdateSupplementalTestimonyService do
  describe "a clear on a bill that has no provisioning row" do
    # A clear always produces {supplemental_testimony: nil}, not an empty
    # attribute list, so it used to INSERT a brand-new row of all nils,
    # fooling the Bill Creator screen.
    it "writes no row at all" do
      bill = create(:bill)

      expect {
        described_class.new(bill: bill, clear_supplemental_testimony: true).call
      }.not_to change(BillLlmProvisioning, :count)

      expect(bill.reload.bill_llm_provisioning).to be_nil
    end

    it "reports that it did nothing" do
      bill = create(:bill)

      outcome = described_class.new(bill: bill, clear_supplemental_testimony: true).call

      expect(outcome).to eq(:noop)
    end
  end

  # The other side of the same boundary: a first paste has a value to
  # store, so it legitimately creates the row — the guard tests the VALUE
  # written, not the clear flag, so this path is unaffected.
  describe "a first paste on a bill that has no provisioning row" do
    it "creates the row and stores the text" do
      bill = create(:bill)

      outcome = described_class.new(
        bill: bill, supplemental_testimony: "Testimony from the hearing."
      ).call

      expect(outcome).to eq(:updated)
      expect(bill.reload.bill_llm_provisioning.supplemental_testimony)
        .to eq("Testimony from the hearing.")
    end
  end

  # And a clear on a row that DOES exist still clears, so the fix narrowed
  # nothing that mattered.
  describe "a clear on a bill that has a provisioning row" do
    it "empties the column" do
      bill = create(:bill)
      provisioning = create(
        :bill_llm_provisioning, bill: bill, supplemental_testimony: "Pasted by mistake."
      )

      outcome = described_class.new(bill: bill, clear_supplemental_testimony: true).call

      expect(outcome).to eq(:updated)
      expect(provisioning.reload.supplemental_testimony).to be_nil
    end
  end
end
