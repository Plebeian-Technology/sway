# frozen_string_literal: true

require "rails_helper"

# Browsing and filtering organizations as a non-admin, plus the props that say
# whether the signed-in user follows or belongs to each one, and the ?following
# filter.
RSpec.describe "Public::OrganizationsController", type: :request do
  include_context "SessionDouble"

  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:other_locale) { create(:sway_locale, city: "Annapolis", state: "maryland", country: "united_states") }

  let(:user) { create(:user).tap { |u| complete_registration_with_active_link(u) } }

  describe "GET /public/organizations" do
    it "is reachable without authentication and returns every locale's orgs as JSON when no locale is given" do
      create(:organization, name: "Alpha", sway_locale: sway_locale)
      create(:organization, name: "Beta", sway_locale: other_locale)

      get "/public/organizations", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      names = body[:organizations].pluck(:name)
      expect(names).to contain_exactly("Alpha", "Beta")
    end

    it "filters by ?locale_id=" do
      create(:organization, name: "Alpha", sway_locale: sway_locale)
      create(:organization, name: "Beta", sway_locale: other_locale)

      get "/public/organizations", params: {locale_id: sway_locale.id},
        headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:organizations].pluck(:name)).to contain_exactly("Alpha")
      expect(body[:applied_filters][:locale_id]).to eq(sway_locale.id.to_s)
      expect(body[:applied_filters][:sway_locale_id]).to eq(sway_locale.id.to_s)
    end

    it "filters by ?sway_locale_id=" do
      create(:organization, name: "Alpha", sway_locale: sway_locale)
      create(:organization, name: "Beta", sway_locale: other_locale)

      get "/public/organizations", params: {sway_locale_id: sway_locale.id},
        headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:organizations].pluck(:name)).to contain_exactly("Alpha")
      expect(body[:applied_filters][:locale_id]).to eq(sway_locale.id.to_s)
      expect(body[:applied_filters][:sway_locale_id]).to eq(sway_locale.id.to_s)
    end

    describe "?org_search=" do
      def org_names_for(params)
        get "/public/organizations", params: params, headers: {"Accept" => "application/json"}
        JSON.parse(response.body, symbolize_names: true)[:organizations].pluck(:name)
      end

      it "returns only organizations whose name contains the text, in any case" do
        create(:organization, name: "Housing Coalition", sway_locale: sway_locale)
        create(:organization, name: "Lighthouse Fund", sway_locale: sway_locale)
        create(:organization, name: "Beta", sway_locale: sway_locale)

        expect(org_names_for(org_search: "HOUS")).to contain_exactly("Housing Coalition", "Lighthouse Fund")
      end

      it "intersects with the locale filter" do
        create(:organization, name: "Housing Baltimore", sway_locale: sway_locale)
        create(:organization, name: "Housing Annapolis", sway_locale: other_locale)

        expect(org_names_for(org_search: "hous", sway_locale_id: sway_locale.id))
          .to contain_exactly("Housing Baltimore")
      end

      it "treats % and _ as literal characters" do
        create(:organization, name: "50% Coalition", sway_locale: sway_locale)
        create(:organization, name: "500 Club", sway_locale: sway_locale)
        create(:organization, name: "a_b Group", sway_locale: sway_locale)
        create(:organization, name: "axb Group", sway_locale: sway_locale)

        expect(org_names_for(org_search: "50%")).to contain_exactly("50% Coalition")
        expect(org_names_for(org_search: "a_b")).to contain_exactly("a_b Group")
      end

      it "echoes the search text in applied_filters, nil when absent" do
        get "/public/organizations", params: {org_search: "hous"}, headers: {"Accept" => "application/json"}
        expect(JSON.parse(response.body, symbolize_names: true)[:applied_filters][:org_search]).to eq("hous")

        get "/public/organizations", headers: {"Accept" => "application/json"}
        applied_filters = JSON.parse(response.body, symbolize_names: true)[:applied_filters]
        expect(applied_filters).to have_key(:org_search)
        expect(applied_filters[:org_search]).to be_nil
      end
    end

    # @lat: [[sway-google-cloud-storage#A stored file name is not an address]]
    it "serializes a bare bucket icon_url as a full escaped storage address" do
      bucket = SwayGoogleCloudStorage::BUCKETS[:ASSETS]
      create(:organization, name: "Alpha", sway_locale: sway_locale,
        icon_url: "baltimore-maryland-united_states/MCB Real Estate-1718656727447.jpg")

      get "/public/organizations", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:organizations].first[:icon_url]).to eq(
        "https://storage.googleapis.com/#{bucket}/baltimore-maryland-united_states/MCB%20Real%20Estate-1718656727447.jpg"
      )
    end

    # follower_count is one of PUBLIC_FIELDS, so to_public_json includes it.
    it "renders the explicit whitelist including follower_count (no admin/internal fields leak)" do
      create(:organization, name: "Alpha", sway_locale: sway_locale)

      get "/public/organizations", headers: {"Accept" => "application/json"}
      body = JSON.parse(response.body, symbolize_names: true)
      payload = body[:organizations].first
      expect(payload.keys).to match_array(%i[id name icon_url sway_locale_id created_at sway_locale_slug follower_count])
    end

    # A signed-out request must NOT get the follow or membership props.
    it "signed-out: no user_follows or is_member_of_org_ids in response" do
      create(:organization, name: "Alpha", sway_locale: sway_locale)

      get "/public/organizations", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body).not_to have_key(:user_follows)
      expect(body).not_to have_key(:is_member_of_org_ids)
    end

    # For a signed-in user the index adds user_follows and is_member_of_org_ids.
    it "signed-in: includes user_follows map and is_member_of_org_ids" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      follow = create(:organization_follow, user: user, organization: org)
      sign_in(user)

      get "/public/organizations", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body).to have_key(:user_follows)
      expect(body[:user_follows]).to eq({org.id.to_s.to_sym => follow.id})
      expect(body).to have_key(:is_member_of_org_ids)
    end

    # These props are consumed as they are by both the web app and the mobile app.
    it "signed-in: includes user_follow_prefs (per-follow) and current_user_org_defaults" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      follow = create(:organization_follow, user: user, organization: org,
        notification_cadence: :daily,
        notify_on_new_position: true,
        notify_on_support_change: false,
        notify_on_summary_change: true)
      sign_in(user)

      get "/public/organizations", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      prefs = body[:user_follow_prefs][org.id.to_s.to_sym]
      expect(prefs).to include(
        follow_id: follow.id,
        notify_on_new_position: true,
        notify_on_support_change: false,
        notify_on_summary_change: true,
        notification_cadence: "daily",
        muted: false
      )
      expect(body[:current_user_org_defaults]).to include(
        notify_on_new_position: true,
        notify_on_support_change: true,
        notify_on_summary_change: true,
        notification_cadence: "every_change"
      )
    end

    it "signed-in: a follow with all event-types off reports muted:true" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      create(:organization_follow, :muted, user: user, organization: org)
      sign_in(user)

      get "/public/organizations", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:user_follow_prefs][org.id.to_s.to_sym][:muted]).to be(true)
    end

    it "signed-out: no user_follow_prefs or current_user_org_defaults (REQ-7 boundary)" do
      create(:organization, name: "Alpha", sway_locale: sway_locale)

      get "/public/organizations", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body).not_to have_key(:user_follow_prefs)
      expect(body).not_to have_key(:current_user_org_defaults)
    end

    # An active member of an org sees that org's id in is_member_of_org_ids.
    it "signed-in active member: is_member_of_org_ids includes the org id" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      create(:user_organization_membership, user: user, organization: org, status: "active")
      sign_in(user)

      get "/public/organizations", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:is_member_of_org_ids]).to include(org.id)
    end

    # Someone who is not a member does not see that org's id in the list.
    it "signed-in non-member: is_member_of_org_ids excludes the org id" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      sign_in(user)

      get "/public/organizations", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:is_member_of_org_ids]).not_to include(org.id)
    end

    # ?following=true returns only the orgs the user follows.
    it "?following=true returns only orgs the signed-in user follows" do
      followed = create(:organization, name: "Followed", sway_locale: sway_locale)
      _other = create(:organization, name: "Other", sway_locale: sway_locale)
      create(:organization_follow, user: user, organization: followed)
      sign_in(user)

      get "/public/organizations", params: {following: "true"},
        headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      names = body[:organizations].pluck(:name)
      expect(names).to contain_exactly("Followed")
    end

    # follower_count is part of each org's payload.
    it "follower_count is present in the org payload" do
      create(:organization, name: "Alpha", sway_locale: sway_locale)

      get "/public/organizations", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:organizations].first).to have_key(:follower_count)
    end

    # A mobile request with a bearer token gets the follow and membership props too.
    it "mobile bearer: includes user_follows + is_member_of_org_ids (REQ-8)" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      follow = create(:organization_follow, user: user, organization: org)
      raw_token = "test-bearer-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user, token: raw_token)

      get "/public/organizations",
        headers: {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body).to have_key(:user_follows)
      expect(body[:user_follows]).to eq({org.id.to_s.to_sym => follow.id})
      expect(body).to have_key(:is_member_of_org_ids)
    end

    # NOTE: This renders a real layout, so it needs the built frontend assets.
    # It used to skip itself for that reason. rails_vite builds them on the
    # first request when they are missing or stale, so it now runs anywhere.
    it "renders the Organizations Inertia component with its prop shape" do
      create(:organization, name: "Alpha", sway_locale: sway_locale)

      get "/public/organizations"

      expect(inertia).to render_component(Pages::ORGANIZATIONS)
      expect(inertia.props.keys).to include("organizations", "applied_filters")
    end

    it "lists only the current locale's organizations on an Inertia request with no locale parameter" do
      create(:organization, name: "Alpha", sway_locale: sway_locale)
      create(:organization, name: "Beta", sway_locale: other_locale)
      cookies_hash[:sway_locale_id] = other_locale.id.to_s

      get "/public/organizations"

      expect(inertia).to render_component(Pages::ORGANIZATIONS)
      expect(inertia.props[:organizations].pluck(:name)).to contain_exactly("Beta")
      expect(inertia.props[:applied_filters][:sway_locale_id]).to eq(other_locale.id.to_s)
      expect(inertia.props[:applied_filters][:locale_id]).to eq(other_locale.id.to_s)
    end

    it "lists the requested locale's organizations on an Inertia request with ?sway_locale_id=" do
      create(:organization, name: "Alpha", sway_locale: sway_locale)
      create(:organization, name: "Beta", sway_locale: other_locale)
      cookies_hash[:sway_locale_id] = other_locale.id.to_s

      get "/public/organizations", params: {sway_locale_id: sway_locale.id}

      expect(inertia.props[:organizations].pluck(:name)).to contain_exactly("Alpha")
      expect(inertia.props[:applied_filters][:sway_locale_id]).to eq(sway_locale.id.to_s)
    end
  end

  describe "GET /public/organizations/:id" do
    it "returns the org payload with explicit fields including follower_count" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)

      get "/public/organizations/#{org.id}", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:organization][:name]).to eq("Alpha")
      expect(body[:organization].keys).to match_array(%i[id name icon_url sway_locale_id created_at sway_locale_slug follower_count])
    end

    it "returns active bill positions via to_public_json" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      bill = create(:bill, sway_locale: sway_locale)
      create(
        :organization_bill_position,
        organization: org,
        bill: bill,
        support: "FOR",
        summary: "Reasoning",
        active: true
      )

      get "/public/organizations/#{org.id}", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:organization_bill_positions].length).to eq(1)
      pos_keys = body[:organization_bill_positions].first.keys
      expect(pos_keys).to match_array(%i[id organization_id bill_id support summary summary_ai_unreviewed active created_at])
    end

    # A signed-out show request must NOT include the follow or membership props.
    it "signed-out: no current_user_follow_id or is_member_of_org_ids" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)

      get "/public/organizations/#{org.id}", headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body, symbolize_names: true)
      expect(body).not_to have_key(:current_user_follow_id)
      expect(body).not_to have_key(:is_member_of_org_ids)
    end

    # For a signed-in user, show adds current_user_follow_id and is_member_of_org_ids.
    it "signed-in: includes current_user_follow_id and is_member_of_org_ids" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      follow = create(:organization_follow, user: user, organization: org)
      sign_in(user)

      get "/public/organizations/#{org.id}", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:current_user_follow_id]).to eq(follow.id)
      expect(body).to have_key(:is_member_of_org_ids)
    end

    # An active member sees their org in is_member_of_org_ids.
    it "signed-in active member: is_member_of_org_ids includes the org id" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      create(:user_organization_membership, user: user, organization: org, status: "active")
      sign_in(user)

      get "/public/organizations/#{org.id}", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:is_member_of_org_ids]).to include(org.id)
    end

    # A member with NO follow row still appears in is_member_of_org_ids.
    it "member with no follow row still appears in is_member_of_org_ids" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      create(:user_organization_membership, user: user, organization: org, status: "active")
      # No OrganizationFollow created — user is a member but has NOT clicked Follow
      sign_in(user)

      get "/public/organizations/#{org.id}", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:current_user_follow_id]).to be_nil
      expect(body[:is_member_of_org_ids]).to include(org.id)
    end

    # The same props on the show page, narrowed to a single org.
    it "signed-in with a follow: user_follow_prefs has the org entry + current_user_org_defaults present" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      follow = create(:organization_follow, user: user, organization: org,
        notification_cadence: :weekly)
      sign_in(user)

      get "/public/organizations/#{org.id}", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:user_follow_prefs][org.id.to_s.to_sym]).to include(
        follow_id: follow.id,
        notification_cadence: "weekly",
        muted: false
      )
      expect(body[:current_user_org_defaults]).to have_key(:notification_cadence)
    end

    # A member with NO follow row gets an empty user_follow_prefs, but still
    # gets the account-wide defaults the frontend fills its picker from.
    it "member with no follow row → user_follow_prefs is empty, defaults present" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      create(:user_organization_membership, user: user, organization: org, status: "active")
      sign_in(user)

      get "/public/organizations/#{org.id}", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:user_follow_prefs]).to eq({})
      expect(body[:current_user_org_defaults]).to include(notification_cadence: "every_change")
    end

    it "signed-out show: no user_follow_prefs or current_user_org_defaults" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)

      get "/public/organizations/#{org.id}", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body).not_to have_key(:user_follow_prefs)
      expect(body).not_to have_key(:current_user_org_defaults)
    end

    # follower_count is part of the show payload.
    it "follower_count is present in the show payload" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)

      get "/public/organizations/#{org.id}", headers: {"Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:organization]).to have_key(:follower_count)
    end

    # A mobile bearer request to show gets current_user_follow_id and is_member_of_org_ids.
    it "mobile bearer: includes current_user_follow_id + is_member_of_org_ids (REQ-8)" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)
      follow = create(:organization_follow, user: user, organization: org)
      raw_token = "test-bearer-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user, token: raw_token)

      get "/public/organizations/#{org.id}",
        headers: {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}

      body = JSON.parse(response.body, symbolize_names: true)
      expect(body[:current_user_follow_id]).to eq(follow.id)
      expect(body).to have_key(:is_member_of_org_ids)
    end

    # NOTE: This renders a real layout, so it needs the built frontend assets.
    # It used to skip itself for that reason. rails_vite builds them on the
    # first request when they are missing or stale, so it now runs anywhere.
    it "renders the Organization Inertia component with its prop shape" do
      org = create(:organization, name: "Alpha", sway_locale: sway_locale)

      get "/public/organizations/#{org.id}"

      expect(inertia).to render_component(Pages::ORGANIZATION)
      expect(inertia.props.keys).to include(
        "organization",
        "organization_bill_positions"
      )
    end
  end

  # @lat: [[query-plan-indexes#A query-cost guard measures growth, not a ceiling]]
  describe "reading the icons costs the same however many organizations there are" do
    it "does not read attachment or blob rows per organization" do
      count_asset_queries = lambda do |org_count|
        sway_locale = create(:sway_locale, :baltimore)
        Organization.destroy_all
        org_count.times do |i|
          org = create(:organization, name: "Icon Org #{i}", sway_locale: sway_locale)
          org.icon.attach(
            io: StringIO.new("icon-bytes"),
            filename: "icon#{i}.png",
            content_type: "image/png"
          )
        end

        seen = [] #: Array[String]
        # `|*, payload|`, matching every other subscriber in spec/. Naming all
        # five parameters instead makes Steep check them against a block type
        # that has fewer, so `payload` types as nil and every use is an error.
        subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          next if /SCHEMA|TRANSACTION/.match?(payload[:name].to_s)

          seen << payload[:sql].to_s
        end
        get "/public/organizations", headers: {"Accept" => "application/json"}
        ActiveSupport::Notifications.unsubscribe(subscription)

        expect(response).to have_http_status(:ok)
        seen.count { |sql| sql.include?("active_storage_attachments") || sql.include?("active_storage_blobs") }
      end

      small = count_asset_queries.call(2)
      # Two zeroes are equal, and a page that stopped drawing icons altogether
      # would read exactly like one holding its cost steady.
      expect(small).to be_positive, "measured no icon reads at all, so this compares nothing"
      expect(count_asset_queries.call(6)).to eq(small)
    end
  end
end
