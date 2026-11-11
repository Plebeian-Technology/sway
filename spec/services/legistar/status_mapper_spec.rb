# frozen_string_literal: true

require "rails_helper"

RSpec.describe Legistar::StatusMapper do
  # @lat: [[legistar-matter-status-mapping#Why Legistar names collapse onto four statuses]]
  describe ".map" do
    # @lat: [[legistar-matter-status-mapping#The Baltimore Legistar status vocabulary]]
    describe "passed statuses" do
      it "maps Baltimore enacted, adopted, confirmed, and passed statuses to passed" do
        expect(described_class.map("Adopted")).to eq("passed")
        expect(described_class.map("Enacted")).to eq("passed")
        expect(described_class.map("Signed by Mayor")).to eq("passed")
        expect(described_class.map("Confirmed")).to eq("passed")
        expect(described_class.map("Confirmed after 3 Meetings without Council Action")).to eq("passed")
        expect(described_class.map("Passed")).to eq("passed")
        expect(described_class.map("Matter Concluded")).to eq("passed")
      end
    end

    describe "failed statuses" do
      it "maps failed, withdrawn, and filed statuses to failed" do
        expect(described_class.map("Failed")).to eq("failed")
        expect(described_class.map("Failed - End of Term")).to eq("failed")
        expect(described_class.map("Withdrawn")).to eq("failed")
        expect(described_class.map("Rules Withdrawn")).to eq("failed")
        expect(described_class.map("Filed")).to eq("failed")
      end
    end

    describe "vetoed statuses" do
      it "maps mayoral veto to vetoed" do
        expect(described_class.map("Vetoed by Mayor")).to eq("vetoed")
      end
    end

    describe "committee statuses" do
      it "maps in-flight, reading, hearing, agenda, and procedural statuses to committee" do
        expect(described_class.map("In Committee")).to eq("committee")
        expect(described_class.map("1st Reader")).to eq("committee")
        expect(described_class.map("First Reading")).to eq("committee")
        expect(described_class.map("2nd Reader")).to eq("committee")
        expect(described_class.map("Second Reading")).to eq("committee")
        expect(described_class.map("3rd Reader, final passage")).to eq("committee")
        expect(described_class.map("3rd Reader, advance from 2nd on same day")).to eq("committee")
        expect(described_class.map("3rd Reader, to be held one meeting")).to eq("committee")
        expect(described_class.map("3rd Reader, to be held two meetings")).to eq("committee")
        expect(described_class.map("3rd Reader, enrolled for final passage")).to eq("committee")
        expect(described_class.map("3rd Reader, recalled from the Mayor's Office")).to eq("committee")
        expect(described_class.map("Introduced In Council")).to eq("committee")
        expect(described_class.map("Introduction of Rule Change")).to eq("committee")
        expect(described_class.map("Nominated")).to eq("committee")
        expect(described_class.map("Before the Mayor")).to eq("committee")
        expect(described_class.map("Return from Mayor's Desk for Further Consideration Requested")).to eq("committee")
        expect(described_class.map("Returned from Mayor's Desk for Further Consideration")).to eq("committee")
        expect(described_class.map("New Business")).to eq("committee")
        expect(described_class.map("Reported to Council")).to eq("committee")
        expect(described_class.map("Referred")).to eq("committee")
        expect(described_class.map("Public Hearing")).to eq("committee")
        expect(described_class.map("Worksession")).to eq("committee")
        expect(described_class.map("Held")).to eq("committee")
        expect(described_class.map("Agenda Ready")).to eq("committee")
        expect(described_class.map("Consent Agenda")).to eq("committee")
        expect(described_class.map("Tabled")).to eq("committee")
      end
    end

    # @lat: [[legistar-matter-status-mapping#Stored values for repaired bills fifty-eight and fifty-nine]]
    describe "specific upstream values for repair targets (Bills 58 and 59)" do
      it "maps MatterFile 24-0599 (Bill 58) status 'Failed - End of Term' to failed" do
        expect(described_class.map("Failed - End of Term")).to eq("failed")
      end

      it "maps MatterFile 24-0592 (Bill 59) status 'Enacted' to passed" do
        expect(described_class.map("Enacted")).to eq("passed")
      end
    end

    describe "whitespace and case tolerance" do
      it "strips leading and trailing whitespace" do
        expect(described_class.map("  Enacted  ")).to eq("passed")
        expect(described_class.map("\tFailed - End of Term\n")).to eq("failed")
        expect(described_class.map("   In Committee ")).to eq("committee")
      end

      it "is case-insensitive" do
        expect(described_class.map("enacted")).to eq("passed")
        expect(described_class.map("ENACTED")).to eq("passed")
        expect(described_class.map("in committee")).to eq("committee")
        expect(described_class.map("vetoed by mayor")).to eq("vetoed")
      end
    end

    # @lat: [[legistar-matter-status-mapping#Ingestion pipeline status boundary]]
    describe "unrecognised and nil inputs" do
      it "returns nil for nil" do
        expect(described_class.map(nil)).to be_nil
      end

      it "returns nil for empty string" do
        expect(described_class.map("")).to be_nil
      end

      it "returns nil for whitespace-only string" do
        expect(described_class.map("   ")).to be_nil
      end

      it "returns nil and logs a warning for unrecognised status name" do
        allow(SwayLogging).to receive(:warn)
        expect(described_class.map("Unrecognised Status XYZ")).to be_nil
        expect(SwayLogging).to have_received(:warn).with(/unrecognised MatterStatusName "Unrecognised Status XYZ"/)
      end

      it "returns nil for non-string types" do
        expect(described_class.map(123)).to be_nil
        expect(described_class.map(true)).to be_nil
        expect(described_class.map([])).to be_nil
      end
    end

    describe "helper methods" do
      it "identifies known status names via .known?" do
        expect(described_class.known?("Enacted")).to be true
        expect(described_class.known?("in committee")).to be true
        expect(described_class.known?("Nonexistent Status")).to be false
        expect(described_class.known?(nil)).to be false
      end

      it "identifies canonical Bill::STATUSES via .canonical?" do
        expect(described_class.canonical?("passed")).to be true
        expect(described_class.canonical?("failed")).to be true
        expect(described_class.canonical?("committee")).to be true
        expect(described_class.canonical?("vetoed")).to be true
        expect(described_class.canonical?("pending")).to be false
        expect(described_class.canonical?("Enacted")).to be false
        expect(described_class.canonical?(nil)).to be false
      end
    end

    describe "model compatibility" do
      it "ensures every mapped status is in Bill::STATUSES" do
        all_raw_statuses = [
          "In Committee", "2nd Reader", "Introduced In Council", "Adopted",
          "3rd Reader, final passage", "Before the Mayor",
          "3rd Reader, advance from 2nd on same day", "3rd Reader, to be held one meeting",
          "3rd Reader, enrolled for final passage", "3rd Reader, recalled from the Mayor's Office",
          "Vetoed by Mayor", "1st Reader", "Enacted", "Nominated", "Signed by Mayor",
          "Introduction of Rule Change", "Confirmed", "Rules Withdrawn", "Matter Concluded",
          "Failed - End of Term", "Worksession", "3rd Reader, to be held two meetings",
          "Confirmed after 3 Meetings without Council Action",
          "Return from Mayor's Desk for Further Consideration Requested",
          "Returned from Mayor's Desk for Further Consideration", "New Business", "Failed",
          "Reported to Council", "Referred", "Public Hearing", "Second Reading", "Passed",
          "Filed", "Withdrawn", "First Reading", "Held", "Agenda Ready", "Consent Agenda", "Tabled"
        ]

        all_raw_statuses.each do |raw_status|
          mapped = described_class.map(raw_status)
          expect(Bill::STATUSES).to include(mapped), "Expected #{mapped} for #{raw_status} to be in Bill::STATUSES"
        end
      end
    end
  end
end
