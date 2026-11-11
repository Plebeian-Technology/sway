# frozen_string_literal: true

require "rails_helper"

RSpec.describe FetchBillsService, "published Congress sponsor ingestion" do
  include ActiveSupport::Testing::TimeHelpers

  # @lat: [[legislation-ingestion#Published sponsor metadata]]
  it "discovers, downloads, and hydrates both chambers with their published sponsors" do
    travel_to(Time.zone.local(2026, 6, 1)) do
      locale = create(:sway_locale, :congress)
      house_sponsor = create(:legislator, sway_locale: locale, external_id: "H000001")
      senate_sponsor = create(:legislator, sway_locale: locale, external_id: "S000001")
      run = create(:legislation_pipeline_run, sway_locale: locale, stages: ["fetch-bills"])
      entries = [
        {"congress" => 119, "type" => "HR", "number" => "1", "originChamber" => "House"},
        {"congress" => 119, "type" => "S", "number" => "1", "originChamber" => "Senate"}
      ]
      stubs = Faraday::Adapter::Test::Stubs.new
      stubs.get("/v3/bill/119") { [200, {}, JSON.generate("bills" => entries)] }
      entries.zip([house_sponsor, senate_sponsor]).each do |entry, sponsor|
        type = entry.fetch("type").to_s.downcase
        detail = entry.merge("title" => "Published #{type} bill", "introducedDate" => "2025-01-09",
          "sponsors" => [{"bioguideId" => sponsor.external_id}])
        stubs.get("/v3/bill/119/#{type}/1") { [200, {}, JSON.generate("bill" => detail)] }
        version = (type == "hr") ? "ih" : "is"
        if type == "hr"
          stubs.get("/content/pkg/BILLS-119hr1ih/pdf/BILLS-119hr1ih.pdf") { [404, {}, "missing"] }
          stubs.get("/v3/bill/119/hr/1/text") do
            [200, {}, JSON.generate("textVersions" => [{"formats" => [
              {"type" => "PDF", "url" => "https://www.congress.gov/119/bills/hr1/BILLS-119hr1eh.pdf"}
            ]}])]
          end
          stubs.get("https://www.congress.gov/119/bills/hr1/BILLS-119hr1eh.pdf") { [200, {}, "%PDF-1.7\nfixture"] }
        else
          stubs.get("/content/pkg/BILLS-119#{type}1#{version}/pdf/BILLS-119#{type}1#{version}.pdf") do
            [200, {"content-type" => "application/pdf"}, "%PDF-1.7\nfixture"]
          end
        end
      end
      conn = Faraday.new(url: "https://api.congress.gov/v3") { |f| f.adapter :test, stubs }

      Dir.mktmpdir("congress-ingestion") do |tmp|
        with_app_config(:legislation, legislation_bills_raw_root: tmp, legislation_bills_text_root: File.join(tmp, "text")) do
          expect(described_class.new(run: run, faraday_conn: conn).call.size).to eq(2)
          expect(Bill.find_by!(sway_locale: locale, external_id: "119-hr-1"))
            .to have_attributes(legislator: house_sponsor, chamber: "house")
          expect(Bill.find_by!(sway_locale: locale, external_id: "119-s-1"))
            .to have_attributes(legislator: senate_sponsor, chamber: "senate")
          expect(run.pipeline_run_bills.count).to eq(2)

          bill_run = run.pipeline_run_bills.find_by!(bill_external_id: "119-hr-1")
          house_pdf = Pathname.new(tmp).join(locale.name, "119-hr-1", "119-hr-1.pdf")
          expect(house_pdf.binread).to start_with("%PDF-")
          extractor = instance_double(MupdfExtractor, call: "A resolution expressing appreciation.")
          expect(MupdfExtractor).to receive(:new).with(house_pdf.to_s).and_return(extractor)
          RunLegislationPipelineJob.new.send(:execute_extract_text, bill_run)
          parsed_bill = Bill.find_by!(sway_locale: locale, external_id: "119-hr-1")
          expect(ParseSectionsService.new(bill: parsed_bill).call.no_sections_found).to be(true)
          expect(parsed_bill.reload.parsed_at).to be_present
          expect(parsed_bill.extracted_text).to eq("A resolution expressing appreciation.")

          entries.zip([house_sponsor, senate_sponsor]).each do |entry, sponsor|
            external_id = "119-#{entry.fetch("type").to_s.downcase}-1"
            directory = Pathname.new(tmp).join(locale.name, external_id)
            expect(directory.join("#{external_id}.pdf").binread).to start_with("%PDF-")
            disk = JSON.parse(directory.join("metadata.json").read)
            expect(disk).to include("legislator_external_id" => sponsor.external_id,
              "chamber" => entry.fetch("originChamber").to_s.downcase)
          end

          Bill.where(sway_locale: locale).destroy_all
          hydration_run = create(:legislation_pipeline_run, sway_locale: locale, stages: ["extract-text"])
          expect(described_class.new(run: hydration_run, faraday_conn: conn).seed_from_disk).to eq(2)
          expect(Bill.find_by!(sway_locale: locale, external_id: "119-hr-1"))
            .to have_attributes(legislator: house_sponsor, chamber: "house")
          expect(Bill.find_by!(sway_locale: locale, external_id: "119-s-1"))
            .to have_attributes(legislator: senate_sponsor, chamber: "senate")
          expect(hydration_run.pipeline_run_bills.count).to eq(2)
        end
      end
      stubs.verify_stubbed_calls
    end
  end
end
