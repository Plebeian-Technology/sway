# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20260915000001_repair_bills_58_and_59")

# @lat: [[bill-status-normalisation#The allowlist is checked on the way in, not on the way past]]
# @lat: [[bill-external-id-normalisation#Why the check is conditional]]
RSpec.describe "RepairBills58And59 data migration", type: :model do
  # steep:ignore:start
  let(:sway_locale) do
    SwayLocale.find_by(city: "baltimore", state: "MD", country: "United States") ||
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
  end
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district, sway_locale: sway_locale) }

  let(:detail_link_58) do
    "https://baltimore.legistar.com/LegislationDetail.aspx?ID=654321&GUID=65C2CB2A-05B9-4D12-99FA-6152E176C3AD"
  end
  let(:detail_link_59) do
    "https://baltimore.legistar.com/LegislationDetail.aspx?ID=123456&GUID=9433015D-2A85-4F15-A3D9-FF69E2E277BA"
  end

  # @lat: [[bill-status-normalisation#Database check constraint against blank status]]
  around do |example|
    ActiveRecord::Base.connection.execute("PRAGMA ignore_check_constraints = ON")
    example.run
  ensure
    ActiveRecord::Base.connection.execute("PRAGMA ignore_check_constraints = OFF")
  end

  let!(:bill_58) do
    bill = create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      title: "Zoning - Conditional Use - Crematorium",
      link: detail_link_58,
      external_id: "temp-58",
      scheduled_release_date_utc: 2.days.ago
    )
    bill.update_columns(external_id: "\t24-0599", status: "")
    bill
  end

  let!(:bill_59) do
    bill = create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      title: "Zoning - Conditional Use Parking Lot - 301 East Lombard Street",
      link: detail_link_59,
      external_id: "temp-59",
      scheduled_release_date_utc: 1.day.ago
    )
    bill.update_columns(external_id: "\t24-0592", status: "", house_vote_date_time_utc: nil)
    bill
  end

  let(:legistar_double) { instance_double(Legistar::Client) }

  before do
    allow(Legistar::Client).to receive(:new).and_return(legistar_double)
  end

  describe "pre-migration defect state" do
    it "confirms both bills are invalid and cannot be updated through ActiveRecord" do
      expect(bill_58.reload).not_to be_valid
      expect(bill_58.errors[:status]).to include("Status can't be blank")
      expect { bill_58.update!(title: "New Title 58") }.to raise_error(ActiveRecord::RecordInvalid)

      expect(bill_59.reload).not_to be_valid
      expect(bill_59.errors[:status]).to include("Status can't be blank")
      expect { bill_59.update!(title: "New Title 59") }.to raise_error(ActiveRecord::RecordInvalid)
      expect {
        bill_59.update!(house_vote_date_time_utc: Time.zone.parse("2024-10-21 17:00:00"))
      }.to raise_error(ActiveRecord::RecordInvalid, /Status can't be blank/)
    end
  end

  describe "#up" do
    it "repairs Bill 58 with stripped external_id and failed status, leaving it valid and saveable" do
      RepairBills58And59.new.up

      reloaded_58 = bill_58.reload
      expect(reloaded_58.external_id).to eq("24-0599")
      expect(reloaded_58.status).to eq("failed")
      expect(reloaded_58.link).to eq(detail_link_58)
      expect(reloaded_58).to be_valid
      expect { reloaded_58.update!(title: "Repaired Title 58") }.not_to raise_error
      expect(reloaded_58.reload.title).to eq("Repaired Title 58")
    end

    it "repairs Bill 59 with stripped external_id and passed status, leaving it valid and saveable" do
      RepairBills58And59.new.up

      reloaded_59 = bill_59.reload
      expect(reloaded_59.external_id).to eq("24-0592")
      expect(reloaded_59.status).to eq("passed")
      expect(reloaded_59.link).to eq(detail_link_59)
      expect(reloaded_59).to be_valid
      expect { reloaded_59.update!(title: "Repaired Title 59") }.not_to raise_error
      expect(reloaded_59.reload.title).to eq("Repaired Title 59")
    end

    it "is idempotent on repeated runs" do
      RepairBills58And59.new.up
      expect { RepairBills58And59.new.up }.not_to raise_error

      expect(bill_58.reload.external_id).to eq("24-0599")
      expect(bill_58.status).to eq("failed")
      expect(bill_59.reload.external_id).to eq("24-0592")
      expect(bill_59.status).to eq("passed")
    end

    it "allows recording final-passage date and fetching votes on Bill 59" do
      RepairBills58And59.new.up

      allow(legistar_double).to receive(:matters)
        .with(filter: "MatterFile eq '24-0592'")
        .and_return([{"MatterId" => 9895, "MatterFile" => "24-0592"}])
      allow(legistar_double).to receive(:matter_histories)
        .with(9895)
        .and_return([
          {
            "MatterHistoryId" => 205092,
            "MatterHistoryActionId" => 43,
            "MatterHistoryActionDate" => "2024-10-21T17:00:00"
          }
        ])

      warnings = []
      allow(Rails.logger).to receive(:warn) { |message| warnings << message.to_s }

      expect { LegislatorVoteFetchJob.run_service_for(bill_59.id) }.not_to raise_error

      expect(bill_59.reload.house_vote_date_time_utc).to eq(Time.zone.parse("2024-10-21 17:00:00"))
      expect(warnings.join("\n")).not_to include("cannot write the final-passage date")
    end

    it "leaves unrelated bills untouched" do
      unrelated_bill = create(:bill, external_id: "24-0100", status: "committee", scheduled_release_date_utc: 3.days.ago)

      expect { RepairBills58And59.new.up }.not_to(change { unrelated_bill.reload.attributes })
    end

    context "with same-numbered rows in a different locale" do
      let(:maryland_locale) do
        SwayLocale.find_by(city: "maryland", region_name: "maryland", country: "united_states") ||
          create(:sway_locale, :maryland)
      end
      let(:maryland_district) { create(:district, sway_locale: maryland_locale) }
      let(:maryland_legislator) { create(:legislator, district: maryland_district, sway_locale: maryland_locale) }

      let!(:other_locale_bill_58) do
        create(
          :bill,
          sway_locale: maryland_locale,
          legislator: maryland_legislator,
          external_id: "24-0599",
          status: "passed",
          title: "Maryland Environment - Crematorium Permitting",
          link: "https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/24-0599",
          scheduled_release_date_utc: 5.days.ago
        )
      end

      let!(:other_locale_bill_59) do
        create(
          :bill,
          sway_locale: maryland_locale,
          legislator: maryland_legislator,
          external_id: "24-0592",
          status: "committee",
          title: "Maryland Transportation - Commercial Parking Facilities",
          link: "https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/24-0592",
          scheduled_release_date_utc: 4.days.ago
        )
      end

      it "leaves same-numbered rows in other locales byte-for-byte unchanged" do
        initial_attrs_58 = other_locale_bill_58.reload.attributes
        initial_attrs_59 = other_locale_bill_59.reload.attributes

        RepairBills58And59.new.up

        expect(other_locale_bill_58.reload.attributes).to eq(initial_attrs_58)
        expect(other_locale_bill_59.reload.attributes).to eq(initial_attrs_59)

        expect(other_locale_bill_58.status).to eq("passed")
        expect(other_locale_bill_58.external_id).to eq("24-0599")
        expect(other_locale_bill_58.link).to eq("https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/24-0599")

        expect(other_locale_bill_59.status).to eq("committee")
        expect(other_locale_bill_59.external_id).to eq("24-0592")
        expect(other_locale_bill_59.link).to eq("https://mgaleg.maryland.gov/mgawebsite/Legislation/Details/24-0592")
      end
    end

    context "when Baltimore locale is absent" do
      let(:congress_locale) do
        SwayLocale.find_by(city: "congress", region_name: "congress", country: "united_states") ||
          create(:sway_locale, :congress)
      end
      let(:congress_district) { create(:district, sway_locale: congress_locale) }
      let(:congress_legislator) { create(:legislator, district: congress_district, sway_locale: congress_locale) }

      let!(:congress_bill) do
        create(
          :bill,
          sway_locale: congress_locale,
          legislator: congress_legislator,
          external_id: "24-0599",
          status: "passed",
          scheduled_release_date_utc: 6.days.ago
        )
      end

      before do
        SwayLocale.where("LOWER(city) = ?", "baltimore").update_all(city: "non_baltimore")
      end

      it "produces no errors and no cross-locale mutation" do
        initial_attrs = congress_bill.reload.attributes

        expect { RepairBills58And59.new.up }.not_to raise_error

        expect(congress_bill.reload.attributes).to eq(initial_attrs)
        expect(congress_bill.status).to eq("passed")
        expect(congress_bill.external_id).to eq("24-0599")
      end
    end
  end

  describe "mutation coverage" do
    it "fails if Bill 58 is left untouched with blank status and leading tab" do
      bill_58.update_columns(external_id: "\t24-0599", status: "")
      bill_59.update_columns(external_id: "24-0592", status: "passed")

      expect(Bill.where(id: bill_58.id).pick(:external_id)).to start_with("\t")
      reloaded_58 = bill_58.reload
      expect(reloaded_58.status).to be_blank
      expect(reloaded_58).not_to be_valid
      expect { reloaded_58.update!(title: "New Title 58") }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it "fails to record final passage date if Bill 59 status is reverted to blank" do
      RepairBills58And59.new.up
      bill_59.update_columns(status: "")

      allow(legistar_double).to receive(:matters)
        .with(filter: "MatterFile eq '24-0592'")
        .and_return([{"MatterId" => 9895, "MatterFile" => "24-0592"}])
      allow(legistar_double).to receive(:matter_histories)
        .with(9895)
        .and_return([
          {
            "MatterHistoryId" => 205092,
            "MatterHistoryActionId" => 43,
            "MatterHistoryActionDate" => "2024-10-21T17:00:00"
          }
        ])

      warnings = []
      allow(Rails.logger).to receive(:warn) { |message| warnings << message.to_s }

      LegislatorVoteFetchJob.run_service_for(bill_59.id)

      expect(bill_59.reload.house_vote_date_time_utc).to be_nil
      expect(warnings.join("\n")).to include("cannot write the final-passage date")
    end
  end

  describe "#down" do
    it "raises ActiveRecord::IrreversibleMigration" do
      expect { RepairBills58And59.new.down }.to raise_error(ActiveRecord::IrreversibleMigration)
    end
  end
  # steep:ignore:end
end
