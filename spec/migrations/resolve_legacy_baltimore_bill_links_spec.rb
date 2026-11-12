# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20261111000004_resolve_legacy_baltimore_bill_links")

# @lat: [[legistar-detail-url-resolution#Backfill procedure for stored Baltimore bills]]
RSpec.describe "ResolveLegacyBaltimoreBillLinks data migration", type: :model do
  let(:migration) { Object.const_get(:ResolveLegacyBaltimoreBillLinks).new }
  let(:generic_search_url) { "https://baltimore.legistar.com/LegislationSearch.aspx" }
  let(:baltimore_locale) do
    SwayLocale.find_or_create_by!(city: "baltimore", state: "maryland", country: "united_states")
  end

  def create_legacy_bill(attrs = {})
    link_value = attrs.key?(:link) ? attrs[:link] : generic_search_url
    bill = create(:bill, {sway_locale: baltimore_locale, scheduled_release_date_utc: nil, link: nil}.merge(attrs.except(:link)))
    bill.update_column(:link, link_value) if link_value.present?
    bill
  end

  def run_migration
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  it "resolves legacy search links to canonical URLs and leaves canonical links untouched idempotently" do
    bill_to_resolve = create_legacy_bill(external_id: "24-0001", link: generic_search_url)
    canonical_existing = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1003&GUID=BBBB-2222"
    unchanged_bill = create(:bill, sway_locale: baltimore_locale, scheduled_release_date_utc: nil, external_id: "24-0003", link: canonical_existing)

    stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Matters?$filter=MatterFile%20eq%20'24-0001'")
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: [{"MatterId" => 1001, "MatterFile" => "24-0001"}].to_json
      )

    stub_request(:head, "https://baltimore.legistar.com/Gateway.aspx?ID=1001&M=L")
      .to_return(
        status: 302,
        headers: {"Location" => "/LegislationDetail.aspx?ID=1001&GUID=AAAA-1111"}
      )

    run_migration

    resolved_url = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1001&GUID=AAAA-1111"
    expect(bill_to_resolve.reload.link).to eq(resolved_url)
    expect(unchanged_bill.reload.link).to eq(canonical_existing)

    expect { run_migration }.not_to change { [bill_to_resolve.reload.link, unchanged_bill.reload.link] }
  end

  it "clears generic link to nil when resolution fails or returns nil while resolvable bills succeed" do
    unresolvable_bill = create_legacy_bill(external_id: "24-FAIL", link: generic_search_url)
    resolvable_bill = create_legacy_bill(external_id: "24-SUCC", link: generic_search_url)

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

    run_migration

    expect(unresolvable_bill.reload.link).to be_nil
    expect(resolvable_bill.reload.link).to eq("https://baltimore.legistar.com/LegislationDetail.aspx?ID=1005&GUID=CCCC-3333")
  end

  it "clears the generic link to nil when the detail URL resolver raises after the matters lookup succeeds" do
    bill = create_legacy_bill(external_id: "24-RESOLVER-FAIL", link: generic_search_url)

    stub_request(:get, "https://webapi.legistar.com/v1/baltimore/Matters?$filter=MatterFile%20eq%20'24-RESOLVER-FAIL'")
      .to_return(
        status: 200,
        headers: {"Content-Type" => "application/json"},
        body: [{"MatterId" => 1007, "MatterFile" => "24-RESOLVER-FAIL"}].to_json
      )

    stub_request(:head, "https://baltimore.legistar.com/Gateway.aspx?ID=1007&M=L")
      .to_raise(RuntimeError.new("unexpected resolver failure"))

    allow(SwayLogging).to receive(:warn)

    expect { run_migration }.not_to raise_error

    expect(bill.reload.link).to be_nil
    expect(SwayLogging).to have_received(:warn).with(a_string_including("detail URL resolver error"))
  end

  it "raises BaltimoreBillLinkBackfillService::PersistenceError when persistence fails" do
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
      run_migration
    }.to raise_error(BaltimoreBillLinkBackfillService::PersistenceError)

    expect(failing_bill.reload.link).to eq(generic_search_url)
  end

  it "raises ActiveRecord::IrreversibleMigration on down" do
    expect { migration.down }.to raise_error(ActiveRecord::IrreversibleMigration)
  end
end
