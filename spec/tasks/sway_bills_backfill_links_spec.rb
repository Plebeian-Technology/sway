# frozen_string_literal: true

require "rails_helper"
require "rake"

# @lat: [[legistar-detail-url-resolution#Backfill procedure for stored Baltimore bills]]
RSpec.describe "sway:bills:backfill_links" do
  let(:generic_search_url) { "https://baltimore.legistar.com/LegislationSearch.aspx" }
  let(:baltimore_locale) do
    SwayLocale.find_or_create_by!(city: "baltimore", state: "maryland", country: "united_states")
  end
  let(:maryland_locale) do
    SwayLocale.find_or_create_by!(city: "maryland", state: "maryland", country: "united_states")
  end

  def create_legacy_bill(attrs = {})
    link_value = attrs.key?(:link) ? attrs[:link] : generic_search_url
    bill = create(:bill, {sway_locale: baltimore_locale, scheduled_release_date_utc: nil, link: nil}.merge(attrs.except(:link)))
    bill.update_column(:link, link_value) if link_value.present?
    bill
  end

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("sway:bills:backfill_links")
  end

  before do
    Rake::Task["sway:bills:backfill_links"].reenable
  end

  describe "backfilling Baltimore bills" do
    it "updates a resolvable bill holding the generic search address to its canonical detail URL" do
      bill = create_legacy_bill(external_id: "24-0001", link: generic_search_url)
      matter_id = 1001
      canonical_url = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1001&GUID=AAAA-1111"

      stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Matters?$filter=MatterFile%20eq%20'24-0001'")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: [{"MatterId" => matter_id, "MatterFile" => "24-0001"}].to_json
        )

      stub_request(:head, "https://baltimore.legistar.com/Gateway.aspx?ID=1001&M=L")
        .to_return(
          status: 302,
          headers: {"Location" => "/LegislationDetail.aspx?ID=1001&GUID=AAAA-1111"}
        )

      Rake::Task["sway:bills:backfill_links"].invoke

      expect(bill.reload.link).to eq(canonical_url)
    end

    it "clears an unresolvable bill holding the generic search address to link: nil" do
      bill = create_legacy_bill(external_id: "24-9999", link: generic_search_url)

      stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Matters?$filter=MatterFile%20eq%20'24-9999'")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: [].to_json
        )

      Rake::Task["sway:bills:backfill_links"].invoke

      expect(bill.reload.link).to be_nil
    end

    it "clears a bill to link: nil when matter exists but Gateway resolution returns nil" do
      bill = create_legacy_bill(external_id: "24-0002", link: generic_search_url)
      matter_id = 1002

      stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Matters?$filter=MatterFile%20eq%20'24-0002'")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: [{"MatterId" => matter_id, "MatterFile" => "24-0002"}].to_json
        )

      stub_request(:head, "https://baltimore.legistar.com/Gateway.aspx?ID=1002&M=L")
        .to_return(status: 404)

      Rake::Task["sway:bills:backfill_links"].invoke

      expect(bill.reload.link).to be_nil
    end

    it "leaves bills already holding valid detail URLs untouched (idempotency)" do
      canonical_url = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1003&GUID=BBBB-2222"
      bill = create(:bill, sway_locale: baltimore_locale, scheduled_release_date_utc: nil, external_id: "24-0003", link: canonical_url)

      Rake::Task["sway:bills:backfill_links"].invoke

      expect(bill.reload.link).to eq(canonical_url)
    end

    it "leaves bills already holding link: nil untouched (idempotency)" do
      bill = create(:bill, sway_locale: baltimore_locale, scheduled_release_date_utc: nil, external_id: "24-0004", link: nil)

      Rake::Task["sway:bills:backfill_links"].invoke

      expect(bill.reload.link).to be_nil
    end

    it "does not touch bills from other locales even if holding a search URL" do
      other_bill = create(:bill, sway_locale: maryland_locale, scheduled_release_date_utc: nil, external_id: "hb0001", link: generic_search_url)

      Rake::Task["sway:bills:backfill_links"].invoke

      expect(other_bill.reload.link).to eq(generic_search_url)
    end

    it "continues processing remaining bills and clears targeted generic link to nil when one bill encounters an upstream transport error" do
      failing_bill = create_legacy_bill(external_id: "24-FAIL", link: generic_search_url)
      succeeding_bill = create_legacy_bill(external_id: "24-SUCC", link: generic_search_url)

      stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Matters?$filter=MatterFile%20eq%20'24-FAIL'")
        .to_raise(Faraday::ConnectionFailed.new("connection reset"))

      stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Matters?$filter=MatterFile%20eq%20'24-SUCC'")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: [{"MatterId" => 1005, "MatterFile" => "24-SUCC"}].to_json
        )

      stub_request(:head, "https://baltimore.legistar.com/Gateway.aspx?ID=1005&M=L")
        .to_return(
          status: 302,
          headers: {"Location" => "/LegislationDetail.aspx?ID=1005&GUID=CCCC-3333"}
        )

      allow(SwayLogging).to receive(:warn)

      expect {
        Rake::Task["sway:bills:backfill_links"].invoke
      }.not_to raise_error

      expect(SwayLogging).to have_received(:warn).with(/24-FAIL/i)
      expect(failing_bill.reload.link).to be_nil
      expect(succeeding_bill.reload.link).to eq("https://baltimore.legistar.com/LegislationDetail.aspx?ID=1005&GUID=CCCC-3333")
      expect(Bill.where(sway_locale: baltimore_locale, link: generic_search_url).count).to eq(0)
    end

    it "aborts with non-zero exit when persistence fails" do
      failing_bill = create_legacy_bill(external_id: "24-FAIL-PERSIST", link: generic_search_url)

      stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Matters?$filter=MatterFile%20eq%20'24-FAIL-PERSIST'")
        .to_return(
          status: 200,
          headers: {"Content-Type" => "application/json"},
          body: [].to_json
        )

      allow_any_instance_of(Bill).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(failing_bill))
      allow(SwayLogging).to receive(:warn)

      expect {
        Rake::Task["sway:bills:backfill_links"].invoke
      }.to raise_error(SystemExit)

      expect(failing_bill.reload.link).to eq(generic_search_url)
    end
  end
end
