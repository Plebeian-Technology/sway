# frozen_string_literal: true

require "rails_helper"

RSpec.describe LegislationIngestionService do
  include ActiveSupport::Testing::TimeHelpers

  let(:maryland) { create(:sway_locale, :maryland) }
  let(:maryland_house_district) { create(:district, sway_locale: maryland, name: "MD-21") }
  let(:maryland_senate_district) { create(:district, sway_locale: maryland, name: "MD-46") }
  let!(:maryland_speaker) do
    legislator = create(:legislator, district: maryland_house_district,
      external_id: "ocd-person/366c0122-84a8-460e-bc98-93d4ca5f0176")
    create(:legislator_term, legislator: legislator, district: maryland_house_district,
      title: "Delegate", term_start_year: 2023, term_end_year: 2027)
    legislator
  end
  let!(:maryland_president) do
    legislator = create(:legislator, district: maryland_senate_district,
      external_id: "ocd-person/86f0d40f-05f4-46a2-9c24-21ff52fdc6fe")
    create(:legislator_term, legislator: legislator, district: maryland_senate_district,
      title: "Senator", term_start_year: 2023, term_end_year: 2027)
    legislator
  end
  let(:service) { described_class.new }
  let(:payload) { {"external_id" => "HB0001", "sway_locale_external_id" => maryland.name} }

  around do |example|
    travel_to(Time.zone.local(2026, 9, 15)) { example.run }
  end

  # @lat: [[legislation-ingestion#Declared fallback associations]]
  it "uses the declared current officeholder for each chamber within one ingestion batch" do
    house = service.upsert_bill_payload(payload)
    senate = service.upsert_bill_payload(payload.merge("external_id" => "SB0001"))

    expect(house).to have_attributes(chamber: "house", legislator: maryland_speaker)
    expect(senate).to have_attributes(chamber: "senate", legislator: maryland_president)
  end

  # @lat: [[legislation-ingestion#Locale and chamber resolution]]
  it "honors an explicit chamber before the bill prefix" do
    bill = service.upsert_bill_payload(payload.merge("chamber" => "senate"))

    expect(bill).to have_attributes(chamber: "senate", legislator: maryland_president)
  end

  it "uses the jurisdiction default when neither a chamber nor a recognized prefix is supplied" do
    bill = service.upsert_bill_payload(payload.merge("external_id" => "TEST-1"))

    expect(bill).to have_attributes(chamber: "house", legislator: maryland_speaker)
  end

  it "uses a supplied legislator before considering the officeholder declaration" do
    legislator = create(:legislator, district: maryland_house_district)
    create(:legislator_term, legislator: legislator, district: maryland_house_district,
      title: "Delegate", term_start_year: 2023, term_end_year: 2027)
    bill = service.upsert_bill_payload(payload.merge("legislator_external_id" => legislator.external_id))

    expect(bill.legislator).to eq(legislator)
  end

  it "preserves an existing association during a repeat ingestion" do
    legislator = create(:legislator, district: maryland_house_district)
    bill = create(:bill, sway_locale: maryland, legislator: legislator, chamber: "house", external_id: "HB0001")

    service.upsert_bill_payload(payload)

    expect(bill.reload.legislator).to eq(legislator)
  end

  # @lat: [[legislation-ingestion#Published sponsor metadata]]
  it "accepts a stored former sponsor from the selected locale" do
    legislator = create(:legislator, sway_locale: maryland)
    create(:legislator_term, legislator: legislator, district: maryland_house_district,
      title: "Delegate", term_start_year: 2019, term_end_year: 2023)
    expect(maryland.legislators).not_to include(legislator)

    bill = service.upsert_bill_payload(payload.merge("legislator_external_id" => legislator.external_id))

    expect(bill.legislator).to eq(legislator)
  end

  it "rejects an explicit foreign-locale sponsor instead of using the declared officeholder" do
    foreign_locale = create(:sway_locale, :congress)
    legislator = create(:legislator, sway_locale: foreign_locale)

    expect { service.upsert_bill_payload(payload.merge("legislator_external_id" => legislator.external_id)) }
      .to raise_error(described_class::IngestionError, /No legislator with external_id=#{legislator.external_id} found for sway_locale=#{maryland.name}/)
    expect(Bill.where(sway_locale: maryland)).to be_empty
  end

  it "replaces an existing fallback with the supplied published sponsor" do
    bill = service.upsert_bill_payload(payload)
    sponsor = create(:legislator, sway_locale: maryland)

    service.upsert_bill_payload(payload.merge("legislator_external_id" => sponsor.external_id))

    expect(bill.reload.legislator).to eq(sponsor)
  end

  it "rejects an unknown sponsor on an existing bill without partially changing it" do
    bill = service.upsert_bill_payload(payload)
    original_title = bill.title

    expect { service.upsert_bill_payload(payload.merge("legislator_external_id" => "unknown", "title" => "Changed")) }
      .to raise_error(described_class::IngestionError, /No legislator with external_id=unknown/)

    expect(bill.reload).to have_attributes(legislator: maryland_speaker, title: original_title)
  end

  it "rejects a declared officeholder whose term has ended instead of using another member" do
    maryland_speaker.legislator_terms.update_all(term_end_year: 2025)
    create(:legislator, district: maryland_house_district)

    expect { service.upsert_bill_payload(payload) }
      .to raise_error(described_class::IngestionError, /No current Speaker of the House.*chamber=house/)
    expect(Bill.where(sway_locale: maryland)).to be_empty
  end

  it "rejects an officeholder whose current term belongs to another jurisdiction" do
    baltimore = create(:sway_locale, :baltimore)
    other_district = create(:district, sway_locale: baltimore)
    maryland_speaker.legislator_terms.update_all(district_id: other_district.id)

    expect { service.upsert_bill_payload(payload) }
      .to raise_error(described_class::IngestionError, /No current Speaker of the House/)
  end

  it "rejects an officeholder whose term is in the wrong chamber" do
    maryland_speaker.legislator_terms.update_all(title: "Senator")

    expect { service.upsert_bill_payload(payload) }
      .to raise_error(described_class::IngestionError, /No current Speaker of the House/)
  end

  it "does not borrow a Maryland officeholder for an undeclared Congress fallback" do
    congress = create(:sway_locale, :congress)

    expect { service.upsert_bill_payload(payload.merge("sway_locale_external_id" => congress.name)) }
      .to raise_error(described_class::IngestionError, /No fallback legislator declared.*congress-congress-united_states/)
  end

  it "does not invent a leader for a bill attributed to both chambers" do
    expect { service.upsert_bill_payload(payload.merge("chamber" => "both")) }
      .to raise_error(described_class::IngestionError, /No fallback legislator declared.*chamber=both/)
  end

  it "hydrates Maryland discovery metadata into correctly associated bills without a Council President" do
    run = create(:legislation_pipeline_run, sway_locale: maryland, stages: ["fetch-bills"])

    Dir.mktmpdir("maryland-bill-ingestion") do |tmp|
      %w[HB0001 SB0001].each_with_index do |external_id, index|
        directory = Pathname.new(tmp).join(maryland.name, external_id)
        directory.mkpath
        directory.join("metadata.json").write(JSON.generate(
          external_id: external_id, matter_id: index + 1, title: external_id,
          bill_number: external_id, matter_type: "Bill"
        ))
      end

      with_app_config(:legislation, legislation_bills_raw_root: tmp) do
        expect(FetchBillsService.new(run: run).seed_from_disk).to eq(2)
      end
    end

    expect(Bill.find_by!(sway_locale: maryland, external_id: "HB0001"))
      .to have_attributes(chamber: "house", legislator: maryland_speaker)
    expect(Bill.find_by!(sway_locale: maryland, external_id: "SB0001"))
      .to have_attributes(chamber: "senate", legislator: maryland_president)
    expect(run.pipeline_run_bills.count).to eq(2)
  end
end
