# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Bootstrap", type: :request do
  describe "GET /api/v1/bootstrap" do
    it "returns the bootstrap envelope for an unauthenticated caller" do
      get "/api/v1/bootstrap", as: :json
      expect(response).to have_http_status(:ok)

      body = json_body
      expect(body.keys).to match_array(
        %i[
          current_user
          locale
          sway_locale
          sway_locales
          bill_of_the_month
          feature_flags
          unread_notification_count
          min_supported_version
          latest_version
        ]
      )
      expect(body[:current_user]).to be_nil
    end

    it "serves the anonymous public envelope when only cookie credentials are present" do
      user = create(:user)
      sign_in(user)

      get "/api/v1/bootstrap", as: :json
      expect(response).to have_http_status(:ok)

      body = json_body
      expect(body[:current_user]).to be_nil
    end

    it "omits user_vote from bill_of_the_month on cookie-only requests" do
      user = create(:user)
      sway_locale = create(:sway_locale)
      bill = create(:bill, sway_locale: sway_locale, scheduled_release_date_utc: 1.day.ago)
      create(:user_vote, user: user, bill: bill, support: "FOR")
      sign_in(user)

      get "/api/v1/bootstrap?sway_locale_id=#{sway_locale.id}", as: :json
      expect(response).to have_http_status(:ok)

      body = json_body
      expect(body[:current_user]).to be_nil
      expect(body.dig(:bill_of_the_month, :user_vote)).to be_nil
    end

    it "returns bearer user when bearer is present even if cookie session for another user exists" do
      cookie_user = create(:user)
      bearer_user = create(:user)
      sign_in(cookie_user)
      headers = authenticate_as(bearer_user)

      get "/api/v1/bootstrap", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:current_user]).to be_a(Hash)
      expect(body[:current_user][:id]).to eq(bearer_user.id)
    end

    it "returns the current_user payload when bearer is present" do
      user = create(:user)
      headers = authenticate_as(user)

      get "/api/v1/bootstrap", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:current_user]).to be_a(Hash)
      expect(body[:current_user][:id]).to eq(user.id)
    end

    # @lat: [[bootstrap-caching-and-rate-limiting#Why the user address has an explicit payload]]
    it "whitelists current_user.address (no lat/lon/street3, adds full_address)" do
      user = create(:user)
      address = create(:address, latitude: 38.9072, longitude: -77.0369)
      create(:user_address, user: user, address: address)
      headers = authenticate_as(user)

      get "/api/v1/bootstrap", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      address_data = json_body[:current_user][:address]
      expect(address_data).to be_a(Hash)
      expect(address_data).not_to have_key(:latitude)
      expect(address_data).not_to have_key("latitude")
      expect(address_data).not_to have_key(:longitude)
      expect(address_data).not_to have_key("longitude")
      expect(address_data).not_to have_key(:street3)
      expect(address_data).not_to have_key("street3")
      expect(address_data).to have_key(:full_address)
      expect(address_data).to have_key(:street)
      expect(address_data).to have_key(:city)
    end

    it "sends the current_user keys the mobile app routes on, with a null address, for an unregistered user" do
      user = create(:user)
      headers = authenticate_as(user)

      get "/api/v1/bootstrap", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      current_user = json_body[:current_user]
      expect(current_user.keys).to match_array(
        %i[id full_name email phone is_registration_complete registration_status
          is_registered_to_vote sms_notifications_enabled theme_mode address
          invite_url is_email_verified]
      )
      expect(current_user[:is_registration_complete]).to be(false)
      expect(current_user[:registration_status]).to eq("pending")
      expect(current_user[:address]).to be_nil
    end

    it "sends the phone of the signed-in user" do
      user = create(:user)
      headers = authenticate_as(user)

      get "/api/v1/bootstrap", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      expect(json_body[:current_user][:phone]).to be_present
      expect(json_body[:current_user][:phone]).to eq(user.phone)
    end

    # @lat: [[bootstrap-caching-and-rate-limiting#Why the user address has an explicit payload]]
    it "sends exactly the address keys the mobile app reads" do
      user = create(:user)
      create(:user_address, user: user, address: create(:address))
      headers = authenticate_as(user)

      get "/api/v1/bootstrap", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      expect(json_body[:current_user][:address].keys).to match_array(
        %i[id street street2 city region_code country postal_code full_address]
      )
    end

    it "sends is_registration_complete as the JSON boolean true for a registered user" do
      user = create(:user, :registered)
      headers = authenticate_as(user)

      get "/api/v1/bootstrap", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      current_user = json_body[:current_user]
      expect(current_user[:is_registration_complete]).to be(true)
      expect(current_user[:registration_status]).to eq("completed")
    end

    # The same "these fields must be absent" check that shared_data_spec.rb makes,
    # applied to the current_user the mobile app receives. Columns that do exist on
    # User but are deliberately left out must not reach a non-admin client.
    # to_sway_json behaves today; this keeps it that way.
    it "excludes sensitive user fields from current_user (login IPs, webauthn_id, sign_in_count, is_admin)" do
      user = create(:user)
      # Force the non-admin case, so is_admin is certain to be absent.
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, ["+10000000000"])
      headers = authenticate_as(user)

      get "/api/v1/bootstrap", headers: headers, as: :json
      expect(response).to have_http_status(:ok)

      current_user = json_body[:current_user]
      %w[current_sign_in_ip last_sign_in_ip webauthn_id sign_in_count is_admin].each do |field|
        expect(current_user).not_to have_key(field.to_sym)
        expect(current_user).not_to have_key(field)
      end
    end

    # theme_mode has to be in the current_user payload, so the mobile app's
    # ThemeProvider can match the person's light or dark setting the moment it starts.
    it "includes theme_mode in current_user payload" do
      user = create(:user, theme_mode: "dark")
      headers = authenticate_as(user)

      get "/api/v1/bootstrap", headers: headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(json_body[:current_user][:theme_mode]).to eq("dark")
    end

    it "respects the two declared version settings" do
      with_app_config(:mobile, mobile_min_version: "1.5.0", mobile_latest_version: "1.6.0") do
        get "/api/v1/bootstrap", as: :json
        expect(json_body[:min_supported_version]).to eq("1.5.0")
        expect(json_body[:latest_version]).to eq("1.6.0")
      end
    end

    it "defaults version fields to 1.0.0 when unset" do
      with_app_config(:mobile) do
        get "/api/v1/bootstrap", as: :json
        expect(json_body[:min_supported_version]).to eq("1.0.0")
        expect(json_body[:latest_version]).to eq("1.0.0")
      end
    end

    # The exact hazard the plan names: a one-decimal-point value read through
    # any automatic caster becomes a Float, which JSON serializes unquoted --
    # the mobile client compares both versions as text.
    it "reports both version numbers as text in the JSON body, never as numbers" do
      with_app_config(:mobile, mobile_min_version: "1.5", mobile_latest_version: "2") do
        get "/api/v1/bootstrap", as: :json
        expect(json_body[:min_supported_version]).to eq("1.5")
        expect(json_body[:min_supported_version]).to be_a(String)
        expect(json_body[:latest_version]).to eq("2")
        expect(json_body[:latest_version]).to be_a(String)
      end
    end

    # Checks on the sway_locales part of the response: which fields it carries, and how
    # it is cached.
    describe "sway_locales in response (D-Phase-34-01)" do
      it "includes sway_locales key in the response" do
        get "/api/v1/bootstrap", as: :json
        expect(response).to have_http_status(:ok)
        expect(json_body).to have_key(:sway_locales)
      end

      it "returns sway_locales as an Array" do
        create(:sway_locale)
        get "/api/v1/bootstrap", as: :json
        expect(json_body[:sway_locales]).to be_an(Array)
      end

      it "includes declared locales and excludes undeclared locales in sway_locales" do
        Rails.cache.clear
        declared_locale = create(:sway_locale, :baltimore)
        undeclared_locale = create(:sway_locale, city: "bethesda", state: "MD", country: "United States")

        get "/api/v1/bootstrap", as: :json

        expect(response).to have_http_status(:ok)
        ids = json_body[:sway_locales].pluck(:id)
        expect(ids).to include(declared_locale.id)
        expect(ids).not_to include(undeclared_locale.id)
      end

      it "each sway_locale element contains only public-allowlist fields (T-34-01-01)" do
        sway_locale = create(:sway_locale)
        get "/api/v1/bootstrap", as: :json
        locales = json_body[:sway_locales]
        expect(locales).not_to be_empty

        # @lat: [[bootstrap-caching-and-rate-limiting#Why show is a single request]]
        public_fields = %i[id name city region_name region_code country
          time_zone icon_url current_session_start_date current_legislative_session_start_date default_bill_chamber
          bill_chambers districts generic_portal_urls nominatim_viewbox nominatim_bounded nominatim_country_codes slug]
        locales.each do |loc|
          expect(loc.keys).to all(be_in(public_fields)),
            "sway_locale element had unexpected keys: #{(loc.keys - public_fields).inspect}"
        end

        found = locales.find { |l| l[:id] == sway_locale.id }
        expect(found).not_to be_nil
        expect(found[:name]).to eq(sway_locale.name)
      end

      it "?sway_locale_id=N selects the requested locale" do
        # The mobile app signs in with a bearer token and has no cookies, so it needs a
        # URL parameter to change locale. There are two locales here, and the parameter
        # has to pick the second one, beating whatever the user's own setting or the
        # default would otherwise give.
        _default = create(:sway_locale, city: "default-city", state: "DC", country: "United States")
        target = create(:sway_locale, city: "target-city", state: "TC", country: "United States")

        get "/api/v1/bootstrap", params: {sway_locale_id: target.id}, as: :json
        expect(response).to have_http_status(:ok)
        expect(json_body[:locale][:id]).to eq(target.id)
      end

      it "fetches sway_locales from cache with the versioned key and 300s TTL (T-34-01-02/03)" do
        # Confirm the controller calls Rails.cache.fetch with the versioned key
        # "api_v1_bootstrap:sway_locales:v1" and a 300-second lifetime. The call is
        # watched and its arguments checked.
        cached_value = [{"id" => 1, "name" => "test"}]
        allow(Rails.cache).to receive(:fetch).and_call_original
        allow(Rails.cache).to receive(:fetch)
          .with("api_v1_bootstrap:sway_locales:v1", expires_in: 300)
          .and_return(cached_value)

        get "/api/v1/bootstrap", as: :json
        expect(response).to have_http_status(:ok)
        expect(Rails.cache).to have_received(:fetch)
          .with("api_v1_bootstrap:sway_locales:v1", expires_in: 300)
        expect(json_body[:sway_locales]).to eq([{id: 1, name: "test"}])
      end
    end

    # @lat: [[bootstrap-caching-and-rate-limiting#Why cached bills are checked for visibility]]
    describe "cached fallback after session archiving" do
      # @type self: BootstrapArchiveSpecContext
      around do |example|
        original_cache = Rails.cache
        Rails.cache = ActiveSupport::Cache::MemoryStore.new
        example.run
      ensure
        Rails.cache = original_cache
      end

      let(:sway_locale) { create(:sway_locale, :baltimore) }
      let!(:session) do
        create(:legislative_session, sway_locale: sway_locale, active: true,
          start_date: Date.current.beginning_of_year, end_date: Date.current.end_of_year)
      end
      let(:prior_session) do
        create(:legislative_session, sway_locale: sway_locale,
          start_date: session.start_date - 1.year, end_date: session.start_date)
      end
      let!(:old_bill) do
        create(:bill, sway_locale: sway_locale, legislative_session: prior_session,
          introduced_date_time_utc: session.start_date - 1.month, scheduled_release_date_utc: nil)
      end
      let(:user) { create(:user) }

      %i[anonymous bearer].each do |caller|
        it "excludes the warmed archived fallback for #{caller} callers with retained votes" do
          vote = create(:user_vote, user: user, bill: old_bill, support: LegislatorVote::Support::FOR)
          headers = (caller == :bearer) ? authenticate_as(user) : {}
          get "/api/v1/bootstrap", params: {sway_locale_id: sway_locale.id}, headers: headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(json_body.dig(:bill_of_the_month, :id)).to eq(old_bill.id)
          expect(Rails.cache.read("api_v1_bootstrap:botm:#{sway_locale.id}")["id"]).to eq(old_bill.id)

          expect(ArchivePreviousSessionBillsService.new(sway_locale: sway_locale).call).to eq(1)
          expect(vote.reload.bill_id).to eq(old_bill.id)
          expect(Rails.cache.read("api_v1_bootstrap:botm:#{sway_locale.id}")["id"]).to eq(old_bill.id)

          get "/api/v1/bootstrap", params: {sway_locale_id: sway_locale.id}, headers: headers, as: :json
          expect(response).to have_http_status(:ok)
          expect(json_body[:bill_of_the_month]).to be_nil
        end
      end

      it "refreshes to a visible same-locale fallback and merges only its vote" do
        create(:user_vote, user: user, bill: old_bill, support: LegislatorVote::Support::FOR)
        headers = authenticate_as(user)
        get "/api/v1/bootstrap", params: {sway_locale_id: sway_locale.id}, headers: headers, as: :json
        expect(json_body.dig(:bill_of_the_month, :id)).to eq(old_bill.id)
        expect(json_body.dig(:bill_of_the_month, :user_vote, :support)).to eq(LegislatorVote::Support::FOR)

        replacement = create(:bill, sway_locale: sway_locale, legislative_session: session,
          scheduled_release_date_utc: nil)
        create(:user_vote, user: user, bill: replacement, support: LegislatorVote::Support::AGAINST)
        expect(ArchivePreviousSessionBillsService.new(sway_locale: sway_locale).call).to eq(1)

        get "/api/v1/bootstrap", params: {sway_locale_id: sway_locale.id}, headers: headers, as: :json
        expect(response).to have_http_status(:ok)
        expect(json_body.dig(:bill_of_the_month, :id)).to eq(replacement.id)
        expect(json_body.dig(:bill_of_the_month, :user_vote)).to eq({support: LegislatorVote::Support::AGAINST})
        expect(Rails.cache.read("api_v1_bootstrap:botm:#{sway_locale.id}")["id"]).to eq(replacement.id)

        get "/api/v1/bootstrap", params: {sway_locale_id: sway_locale.id}, as: :json
        expect(json_body.dig(:bill_of_the_month, :id)).to eq(replacement.id)
        expect(json_body.dig(:bill_of_the_month, :user_vote)).to be_nil
      end

      it "preserves another locale's visible cached featured bill" do
        other_locale = create(:sway_locale, :maryland)
        featured = create(:bill, :bill_of_the_month, sway_locale: other_locale)
        get "/api/v1/bootstrap", params: {sway_locale_id: other_locale.id}, as: :json
        cached_payload = json_body[:bill_of_the_month]
        expect(cached_payload[:id]).to eq(featured.id)
        featured.update!(title: "Changed after warming the cache")

        expect(ArchivePreviousSessionBillsService.new(sway_locale: sway_locale).call).to eq(1)
        get "/api/v1/bootstrap", params: {sway_locale_id: other_locale.id}, as: :json
        expect(response).to have_http_status(:ok)
        expect(json_body[:bill_of_the_month]).to eq(cached_payload)
      end
    end

    describe "featured bill in response" do
      let(:sway_locale) { create(:sway_locale) }
      let!(:bill) { create(:bill, :bill_of_the_month, sway_locale: sway_locale) }

      it "returns the featured bill only under bill_of_the_month" do
        get "/api/v1/bootstrap", params: {sway_locale_id: sway_locale.id}, as: :json
        expect(response).to have_http_status(:ok)

        body = json_body
        expect(body[:bill_of_the_month]).to be_present
        expect(body[:bill_of_the_month][:id]).to eq(bill.id)
        expect(body.keys.grep(/bill_of_the_/)).to eq([:bill_of_the_month])
      end

      it "caches using the botm cache key namespace" do
        allow(Rails.cache).to receive(:fetch).and_call_original

        get "/api/v1/bootstrap", params: {sway_locale_id: sway_locale.id}, as: :json
        expect(response).to have_http_status(:ok)
        expect(Rails.cache).to have_received(:fetch)
          .with("api_v1_bootstrap:botm:#{sway_locale.id}", expires_in: 60)
      end

      it "merges user_vote into bill_of_the_month" do
        user = create(:user)
        create(:user_vote, user: user, bill: bill, support: LegislatorVote::Support::FOR)
        headers = authenticate_as(user)

        get "/api/v1/bootstrap", params: {sway_locale_id: sway_locale.id}, headers: headers, as: :json
        expect(response).to have_http_status(:ok)

        body = json_body
        expect(body[:bill_of_the_month][:user_vote]).to eq({support: LegislatorVote::Support::FOR})
      end

      it "returns nil for bill_of_the_month when locale has no featured bill" do
        locale_without_bill = create(:sway_locale)

        get "/api/v1/bootstrap", params: {sway_locale_id: locale_without_bill.id}, as: :json
        expect(response).to have_http_status(:ok)

        body = json_body
        expect(body[:bill_of_the_month]).to be_nil
      end
    end
  end

  describe ".expire_botm_cache" do
    include_context "with in-memory Rails.cache"

    let(:sway_locale) { create(:sway_locale, :baltimore) }
    let(:other_locale) { create(:sway_locale, :maryland) }

    it "deletes the cached featured bill for the specified locale without affecting other locales" do
      Rails.cache.write("api_v1_bootstrap:botm:#{sway_locale.id}", {"id" => 123})
      Rails.cache.write("api_v1_bootstrap:botm:#{other_locale.id}", {"id" => 456})

      Api::V1::BootstrapController.expire_botm_cache(sway_locale.id)

      expect(Rails.cache.read("api_v1_bootstrap:botm:#{sway_locale.id}")).to be_nil
      expect(Rails.cache.read("api_v1_bootstrap:botm:#{other_locale.id}")).to eq({"id" => 456})
    end

    it "does nothing when sway_locale_id is nil" do
      Rails.cache.write("api_v1_bootstrap:botm:#{sway_locale.id}", {"id" => 123})

      Api::V1::BootstrapController.expire_botm_cache(nil)

      expect(Rails.cache.read("api_v1_bootstrap:botm:#{sway_locale.id}")).to eq({"id" => 123})
    end
  end
end
