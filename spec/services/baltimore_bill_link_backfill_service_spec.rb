# frozen_string_literal: true

require "rails_helper"

# @lat: [[legistar-detail-url-resolution#Backfill procedure for stored Baltimore bills]]
# steep:ignore:start
RSpec.describe BaltimoreBillLinkBackfillService do
  let(:baltimore_locale) do
    SwayLocale.find_or_create_by!(city: "baltimore", state: "maryland", country: "united_states")
  end
  let(:generic_search_url) { "https://baltimore.legistar.com/LegislationSearch.aspx" }
  let(:legistar_client) { instance_spy(Legistar::Client) }
  let(:detail_url_resolver) { instance_spy(Legistar::DetailUrlResolver) }
  let(:service) do
    described_class.new(
      sway_locale: baltimore_locale,
      legistar_client: legistar_client,
      detail_url_resolver: detail_url_resolver
    )
  end

  def create_legacy_bill(attrs = {})
    link_value = attrs.key?(:link) ? attrs[:link] : generic_search_url
    bill = create(:bill, {sway_locale: baltimore_locale, scheduled_release_date_utc: nil, link: nil}.merge(attrs.except(:link)))
    bill.update_column(:link, link_value) if link_value.present?
    bill
  end

  describe "#call" do
    it "resolves and updates bills with canonical detail URLs" do
      bill = create_legacy_bill(external_id: "24-0001", link: generic_search_url)
      canonical_url = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1001&GUID=AAAA-1111"

      allow(legistar_client).to receive(:matters)
        .with(filter: "MatterFile eq '24-0001'")
        .and_return([{"MatterId" => 1001}])
      allow(detail_url_resolver).to receive(:resolve).with(1001).and_return(canonical_url)

      stats = service.call

      expect(bill.reload.link).to eq(canonical_url)
      expect(stats[:resolved]).to eq(1)
      expect(stats[:cleared]).to eq(0)
    end

    it "clears bills to nil when matter is not found in Legistar" do
      bill = create_legacy_bill(external_id: "24-9999", link: generic_search_url)

      allow(legistar_client).to receive(:matters)
        .with(filter: "MatterFile eq '24-9999'")
        .and_return([])

      stats = service.call

      expect(bill.reload.link).to be_nil
      expect(stats[:resolved]).to eq(0)
      expect(stats[:cleared]).to eq(1)
    end

    it "clears bills to nil when detail URL resolver returns nil" do
      bill = create_legacy_bill(external_id: "24-0002", link: generic_search_url)

      allow(legistar_client).to receive(:matters)
        .with(filter: "MatterFile eq '24-0002'")
        .and_return([{"MatterId" => 1002}])
      allow(detail_url_resolver).to receive(:resolve).with(1002).and_return(nil)

      stats = service.call

      expect(bill.reload.link).to be_nil
      expect(stats[:cleared]).to eq(1)
    end

    it "detects link collision and sets link to nil instead of raising" do
      existing_link = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1003&GUID=COLLIDE"
      create(:bill, sway_locale: baltimore_locale, scheduled_release_date_utc: nil, link: existing_link)

      colliding_bill = create_legacy_bill(external_id: "24-0003", link: generic_search_url)

      allow(legistar_client).to receive(:matters)
        .with(filter: "MatterFile eq '24-0003'")
        .and_return([{"MatterId" => 1003}])
      allow(detail_url_resolver).to receive(:resolve).with(1003).and_return(existing_link)
      allow(SwayLogging).to receive(:warn)

      stats = service.call

      expect(SwayLogging).to have_received(:warn).with(/collision/i)
      expect(colliding_bill.reload.link).to be_nil
      expect(stats[:cleared]).to eq(1)
    end

    it "ignores bills that already have valid detail URLs or nil (idempotency)" do
      canonical_url = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1004&GUID=BBBB-2222"
      bill_with_url = create(:bill, sway_locale: baltimore_locale, scheduled_release_date_utc: nil, external_id: "24-0004", link: canonical_url)
      bill_with_nil = create(:bill, sway_locale: baltimore_locale, scheduled_release_date_utc: nil, external_id: "24-0005", link: nil)

      stats = service.call

      expect(bill_with_url.reload.link).to eq(canonical_url)
      expect(bill_with_nil.reload.link).to be_nil
      expect(legistar_client).not_to have_received(:matters)
      expect(stats[:processed]).to eq(0)
    end

    it "clears targeted generic link to nil and continues processing when upstream matter lookup encounters an exception" do
      bill_upstream_err = create_legacy_bill(external_id: "24-UPSTREAM-FAIL", link: generic_search_url)
      bill_ok = create_legacy_bill(external_id: "24-OK", link: generic_search_url)
      canonical_url = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1005&GUID=CCCC-3333"

      allow(legistar_client).to receive(:matters)
        .with(filter: "MatterFile eq '24-UPSTREAM-FAIL'")
        .and_raise(Legistar::Client::Error, "Connection timeout")
      allow(legistar_client).to receive(:matters)
        .with(filter: "MatterFile eq '24-OK'")
        .and_return([{"MatterId" => 1005}])
      allow(detail_url_resolver).to receive(:resolve).with(1005).and_return(canonical_url)
      allow(SwayLogging).to receive(:warn)

      stats = service.call

      expect(SwayLogging).to have_received(:warn).with(/24-UPSTREAM-FAIL/i)
      expect(bill_upstream_err.reload.link).to be_nil
      expect(bill_ok.reload.link).to eq(canonical_url)
      expect(stats[:cleared]).to eq(1)
      expect(stats[:resolved]).to eq(1)
      expect(stats[:failed]).to eq(0)
    end

    it "records failure and continues processing remaining bills when persistence fails" do
      failing_bill = create_legacy_bill(external_id: "24-FAIL-SAVE", link: generic_search_url)
      bill_ok = create_legacy_bill(external_id: "24-OK2", link: generic_search_url)
      canonical_url = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=1006&GUID=DDDD-4444"

      allow(legistar_client).to receive(:matters)
        .with(filter: "MatterFile eq '24-FAIL-SAVE'")
        .and_return([{"MatterId" => 1006}])
      allow(detail_url_resolver).to receive(:resolve).with(1006).and_return(canonical_url)
      allow(legistar_client).to receive(:matters)
        .with(filter: "MatterFile eq '24-OK2'")
        .and_return([{"MatterId" => 1007}])
      allow(detail_url_resolver).to receive(:resolve).with(1007).and_return(canonical_url)

      allow(Bill).to receive(:find_each).and_call_original
      allow_any_instance_of(Bill).to receive(:update!).and_wrap_original do |m, *args, **kwargs|
        if m.receiver.external_id == "24-FAIL-SAVE"
          raise ActiveRecord::RecordInvalid.new(m.receiver)
        else
          m.call(*args, **kwargs)
        end
      end
      allow(SwayLogging).to receive(:warn)

      stats = service.call

      expect(SwayLogging).to have_received(:warn).with(/24-FAIL-SAVE/i)
      expect(failing_bill.reload.link).to eq(generic_search_url)
      expect(bill_ok.reload.link).to eq(canonical_url)
      expect(stats[:failed]).to eq(1)
      expect(stats[:resolved]).to eq(1)
    end

    it "raises PersistenceError when persistence fails and raise_on_failure is true" do
      failing_bill = create_legacy_bill(external_id: "24-FAIL-RAISE", link: generic_search_url)
      service_with_raise = described_class.new(
        sway_locale: baltimore_locale,
        legistar_client: legistar_client,
        detail_url_resolver: detail_url_resolver,
        raise_on_failure: true
      )

      allow(legistar_client).to receive(:matters)
        .with(filter: "MatterFile eq '24-FAIL-RAISE'")
        .and_return([])

      allow_any_instance_of(Bill).to receive(:update!).and_raise(ActiveRecord::RecordInvalid.new(failing_bill))
      allow(SwayLogging).to receive(:warn)

      expect {
        service_with_raise.call
      }.to raise_error(BaltimoreBillLinkBackfillService::PersistenceError, /failed persistence/)

      expect(failing_bill.reload.link).to eq(generic_search_url)
    end

    it "derives client dynamically from legislation_rules and accepts client: kwarg" do
      custom_locale = instance_double(
        SwayLocale,
        name: "test-locale",
        jurisdiction_rules: instance_double(
          SwayLocale::JurisdictionRules,
          legislation_rules: {client: "custom_city"}
        )
      )
      client_double = instance_spy(Legistar::Client)
      custom_service = described_class.new(
        sway_locale: custom_locale,
        client: client_double,
        detail_url_resolver: detail_url_resolver
      )
      expect(custom_service.instance_variable_get(:@client)).to eq(client_double)
    end

    it "instantiates Legistar::Client with client from legislation_rules when no client is passed" do
      custom_locale = instance_double(
        SwayLocale,
        name: "test-locale",
        jurisdiction_rules: instance_double(
          SwayLocale::JurisdictionRules,
          legislation_rules: {client: "custom_city"}
        )
      )
      allow(Legistar::Client).to receive(:new).with(client: "custom_city").and_return(instance_spy(Legistar::Client))
      described_class.new(
        sway_locale: custom_locale,
        detail_url_resolver: detail_url_resolver
      )
      expect(Legistar::Client).to have_received(:new).with(client: "custom_city")
    end

    it "does not touch generic search links on bills belonging to Maryland or Congress locales" do
      maryland_locale = create(:sway_locale, :maryland)
      congress_locale = create(:sway_locale, :congress)
      md_bill = create(:bill, external_id: "MD-HB100", sway_locale: maryland_locale, link: nil)
      md_bill.update_column(:link, generic_search_url)
      us_bill = create(:bill, external_id: "US-HR100", sway_locale: congress_locale, link: nil)
      us_bill.update_column(:link, generic_search_url)
      balt_bill = create_legacy_bill(external_id: "24-BALT", link: generic_search_url)
      canonical = "https://baltimore.legistar.com/LegislationDetail.aspx?ID=5001&GUID=GUID-5001"

      allow(legistar_client).to receive(:matters)
        .with(filter: "MatterFile eq '24-BALT'")
        .and_return([{"MatterId" => 5001}])
      allow(detail_url_resolver).to receive(:resolve).with(5001).and_return(canonical)

      stats = service.call

      expect(balt_bill.reload.link).to eq(canonical)
      expect(md_bill.reload.link).to eq(generic_search_url)
      expect(us_bill.reload.link).to eq(generic_search_url)
      expect(stats[:processed]).to eq(1)
      expect(stats[:resolved]).to eq(1)
    end
  end
end
# steep:ignore:end
