# frozen_string_literal: true

require "rails_helper"

# @lat: [[organization-follows-controller]]
RSpec.describe "OrganizationTracksController", type: :request do
  include_context "SessionDouble"

  let(:user) { create(:user).tap { |u| complete_registration_with_active_link(u) } }
  let(:organization) { create(:organization) }

  # ─── POST /organization_tracks ──────────────────────────────────────────────

  describe "POST /organization_tracks" do
    # @lat: [[query-parameter-navigation-carry#Query parameter navigation carry#Centralized interception mechanism#Server redirect carry follows real form writes]]
    it "carries query state through the form redirect and renders the organization page" do
      sign_in(user)
      referer = "http://www.example.com/public/organizations/#{organization.id}"

      post "/organization_tracks?org_tab=members&sway_locale_id=#{organization.sway_locale_id}",
        params: {organization_id: organization.id},
        headers: {"HTTP_REFERER" => referer}

      expect(response).to have_http_status(:redirect)
      expect(URI.decode_www_form(URI.parse(response.location).query.to_s)).to contain_exactly(
        ["org_tab", "members"], ["sway_locale_id", organization.sway_locale_id.to_s]
      )

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::ORGANIZATION)
      expect(inertia.props.deep_symbolize_keys.dig(:organization, :id)).to eq(organization.id)
    end

    it "carries a JSON form URL parameter into the real Inertia destination state" do
      membership = create(:user_organization_membership, user: user, organization: organization, status: :active)
      sign_in(user)
      referer = "http://www.example.com#{organization_membership_path(organization_id: organization.id, id: membership.id)}"

      post "/organization_tracks?org_tab=members&sway_locale_id=42",
        params: {organization_id: organization.id}.to_json,
        headers: {
          "CONTENT_TYPE" => "application/json",
          "HTTP_ACCEPT" => "text/html",
          "HTTP_REFERER" => referer
        }

      expect(response).to have_http_status(:redirect)
      expect(URI.decode_www_form(URI.parse(response.location).query.to_s)).to contain_exactly(
        ["org_tab", "members"], ["sway_locale_id", "42"]
      )

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::USER_ORGANIZATION_MEMBERSHIP)
      expect(inertia.props.deep_symbolize_keys.dig(:tab)).to eq("members")
    end

    it "keeps a client-cleared highlight absent through the form redirect" do
      membership = create(:user_organization_membership, user: user, organization: organization, status: :active)
      sign_in(user)
      referer = "http://www.example.com#{organization_membership_path(organization_id: organization.id, id: membership.id)}?org_tab=members"
      request_url = "/organization_tracks?org_tab=members"

      expect(URI.parse(request_url).query).not_to include("highlight_bill_id")

      post request_url,
        params: {organization_id: organization.id},
        headers: {"HTTP_REFERER" => referer}

      expect(response).to have_http_status(:redirect)
      expect(response.location).not_to include("highlight_bill_id")

      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::USER_ORGANIZATION_MEMBERSHIP)
      expect(inertia.props.deep_symbolize_keys.dig(:tab)).to eq("members")
    end

    it "by a signed-in user creates a follow row" do
      sign_in(user)

      expect {
        # Before this route existed, the call raised ActionController::RoutingError.
        post "/organization_tracks", params: {organization_id: organization.id}
      }.to change(OrganizationTrack, :count).by(1)

      expect(response.status).not_to eq(404)
    end

    it "is idempotent on the unique (user_id, organization_id)" do
      sign_in(user)

      post "/organization_tracks", params: {organization_id: organization.id}

      expect {
        post "/organization_tracks", params: {organization_id: organization.id}
      }.not_to change(OrganizationTrack, :count)
    end

    it "stays idempotent under a concurrent double-POST that races the insert (IN-07)" do
      # Act out the losing half of a race. The other request's insert already
      # landed, so this request's find_or_create_by! hits the unique index on
      # (user_id, organization_id) and raises RecordNotUnique. The controller
      # has to look the row up again and succeed, NOT 500.
      create(:organization_track, user: user, organization: organization)
      sign_in(user)

      allow_any_instance_of(ActiveRecord::Associations::CollectionProxy)
        .to receive(:find_or_create_by!)
        .and_raise(ActiveRecord::RecordNotUnique.new("duplicate key"))

      expect {
        post "/organization_tracks", params: {organization_id: organization.id}
      }.not_to change(OrganizationTrack, :count)

      expect(response).to have_http_status(:redirect).or have_http_status(:see_other)
    end

    it "an unauthenticated POST is rejected (not 200)" do
      # Nobody is signed in, so authenticate_sway_user! must redirect or 401.
      post "/organization_tracks", params: {organization_id: organization.id}

      expect(response.status).not_to eq(200)
      expect(OrganizationTrack.count).to eq(0)
    end

    it "the web path returns a redirect after a successful create" do
      sign_in(user)

      post "/organization_tracks", params: {organization_id: organization.id}

      # A redirect after the write, so a refresh cannot resubmit — any 3xx.
      expect(response).to have_http_status(:redirect)
        .or have_http_status(:see_other)
    end

    it "the mobile bearer path returns JSON" do
      raw_token = "test-bearer-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user, token: raw_token)

      post "/organization_tracks",
        params: {organization_id: organization.id},
        headers: {
          "Authorization" => "Bearer #{raw_token}",
          "Accept" => "application/json"
        }

      # The mobile branch of render_inertia_or_json answers with JSON.
      expect(response.content_type).to include("application/json")
    end
  end

  # ─── DELETE /organization_tracks/:id ────────────────────────────────────────

  describe "DELETE /organization_tracks/:id" do
    it "removes the follow row" do
      follow = create(:organization_track, user: user, organization: organization)
      sign_in(user)

      expect {
        # Before this route existed, the call raised ActionController::RoutingError.
        delete "/organization_tracks/#{follow.id}"
      }.to change(OrganizationTrack, :count).by(-1)
    end
  end

  # ─── PATCH /organization_tracks/:id/preferences ─────────────────────────────

  describe "PATCH /organization_tracks/:id/preferences" do
    it "updates per-follow preference columns" do
      follow = create(:organization_track, user: user, organization: organization,
        notification_cadence: :every_change,
        notify_on_new_position: true,
        notify_on_support_change: true)
      sign_in(user)

      # Before this route existed, the call raised ActionController::RoutingError.
      patch "/organization_tracks/#{follow.id}/preferences",
        params: {
          organization_track: {
            notification_cadence: "daily",
            notify_on_support_change: false
          }
        }

      follow.reload
      expect(follow.notification_cadence).to eq("daily")
      expect(follow.notify_on_support_change).to be(false)
    end
  end

  # ─── Cross-user authorization ────────────────────────────────────────────────
  # set_follow looks the row up with current_user.organization_tracks.find(...),
  # so using ANOTHER user's follow id must 404 through RecordNotFound and never
  # touch that row — no edit, no delete.
  describe "cross-user authorization" do
    let(:other_user) { create(:user).tap { |u| complete_registration_with_active_link(u) } }
    let(:other_follow) do
      create(:organization_track, user: other_user, organization: organization,
        notification_cadence: :every_change,
        notify_on_support_change: true)
    end

    it "DELETE against another user's follow id returns 404 and leaves the row intact" do
      sign_in(user)
      # other_follow is lazy, so touch it here to create the row BEFORE the
      # expect block. Then any change in the count can only come from the
      # DELETE, not from the row being created.
      follow_id = other_follow.id

      expect {
        delete "/organization_tracks/#{follow_id}"
      }.not_to change(OrganizationTrack, :count)

      expect(response).to have_http_status(:not_found)
      expect(OrganizationTrack.exists?(follow_id)).to be(true)
    end

    it "PATCH preferences against another user's follow id returns 404 and leaves the row unchanged" do
      sign_in(user)

      patch "/organization_tracks/#{other_follow.id}/preferences",
        params: {
          organization_track: {
            notification_cadence: "daily",
            notify_on_support_change: false
          }
        }

      expect(response).to have_http_status(:not_found)
      other_follow.reload
      expect(other_follow.notification_cadence).to eq("every_change")
      expect(other_follow.notify_on_support_change).to be(true)
    end
  end
end
