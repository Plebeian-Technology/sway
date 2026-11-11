# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::NotificationPreferences", type: :request do
  let!(:user) { create(:user) }

  before do
    NotificationPreference.seed_defaults_for(user)
  end

  describe "GET /api/v1/notification_preferences" do
    it "returns the stored toggles for current_user and only botm_announcement for the monthly bill" do
      headers = authenticate_as(user)
      get "/api/v1/notification_preferences", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body.pluck(:key)).to eq(NotificationPreference::KEYS.sort)

      botm = body.find { |row| row[:key] == "botm_announcement" }
      expect(botm[:enabled]).to be(true)
    end

    it "returns only botm_announcement when it is the only stored row" do
      user.notification_preferences.where.not(key: "botm_announcement").destroy_all
      headers = authenticate_as(user)
      get "/api/v1/notification_preferences", headers: headers, as: :json

      expect(json_body.pluck(:key)).to eq(["botm_announcement"])
    end

    it "returns 401 without bearer" do
      get "/api/v1/notification_preferences", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/notification_preferences/:key" do
    it "updates the canonical botm_announcement key" do
      headers = authenticate_as(user)
      patch "/api/v1/notification_preferences/botm_announcement",
        params: {enabled: false},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:key]).to eq("botm_announcement")
      expect(body[:enabled]).to be(false)
      expect(user.notification_preferences.find_by(key: "botm_announcement").enabled).to be(false)
    end

    it "toggles enabled for a known key" do
      headers = authenticate_as(user)
      patch "/api/v1/notification_preferences/legislator_voted",
        params: {enabled: true},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:key]).to eq("legislator_voted")
      expect(body[:enabled]).to be(true)
      expect(user.notification_preferences.find_by(key: "legislator_voted").enabled).to be(true)
    end

    it "returns 404 unknown_preference for an unknown key" do
      headers = authenticate_as(user)
      patch "/api/v1/notification_preferences/nonsense_key",
        params: {enabled: true},
        headers: headers,
        as: :json

      # The route only accepts lowercase letters and underscores, so anything with a
      # digit never gets this far. A key that looks right but is not in
      # NotificationPreference::KEYS does reach the controller, and comes back as a 404
      # with the code unknown_preference.
      expect(response).to have_http_status(:not_found)
      expect(json_body.dig(:error, :code)).to eq("unknown_preference")
    end

    # @lat: [[org-notification-cascade-and-defaults#Why update creates the preference row on write]]
    it "creates-on-write and enables an allowlisted key that has no row yet" do
      user.notification_preferences.find_by(key: "org_position_taken").destroy!
      expect(user.notification_preferences.find_by(key: "org_position_taken")).to be_nil

      headers = authenticate_as(user)
      patch "/api/v1/notification_preferences/org_position_taken",
        params: {enabled: true},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:key]).to eq("org_position_taken")
      expect(body[:enabled]).to be(true)
      expect(user.notification_preferences.find_by(key: "org_position_taken").enabled).to be(true)
    end

    it "creates-on-write canonical botm_announcement if missing" do
      user.notification_preferences.find_by(key: "botm_announcement").destroy!
      headers = authenticate_as(user)
      patch "/api/v1/notification_preferences/botm_announcement",
        params: {enabled: true},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:key]).to eq("botm_announcement")
      expect(body[:enabled]).to be(true)
      expect(user.notification_preferences.find_by(key: "botm_announcement").enabled).to be(true)
    end

    it "coerces string 'false' and '0' to boolean false" do
      headers = authenticate_as(user)

      patch "/api/v1/notification_preferences/botm_announcement",
        params: {enabled: "false"},
        headers: headers,
        as: :json
      expect(response).to have_http_status(:ok)
      expect(user.notification_preferences.find_by(key: "botm_announcement").enabled).to be(false)

      user.notification_preferences.find_by(key: "botm_announcement").update!(enabled: true)
      patch "/api/v1/notification_preferences/botm_announcement",
        params: {enabled: "0"},
        headers: headers,
        as: :json
      expect(response).to have_http_status(:ok)
      expect(user.notification_preferences.find_by(key: "botm_announcement").enabled).to be(false)
    end
  end

  # The mobile screen for a user's site-wide organization notification defaults, read
  # and written. Switching a default off spreads to every organization they follow;
  # switching one on does not. Same rules as the web's update_organization_defaults.
  describe "GET /api/v1/notification_preferences/org_defaults" do
    it "returns the 5 global org-default fields for the bearer user" do
      user.update!(
        org_position_cadence_default: :weekly,
        notify_on_new_position_default: true,
        notify_on_support_change_default: false,
        notify_on_summary_change_default: true
      )
      user.notification_preferences.find_by(key: "org_position_taken").update!(enabled: false)

      headers = authenticate_as(user)
      get "/api/v1/notification_preferences/org_defaults", headers: headers, as: :json

      expect(response).to have_http_status(:ok)
      body = json_body
      expect(body[:org_position_taken]).to be(false)
      expect(body[:org_position_cadence_default]).to eq("weekly")
      expect(body[:notify_on_new_position_default]).to be(true)
      expect(body[:notify_on_support_change_default]).to be(false)
      expect(body[:notify_on_summary_change_default]).to be(true)
    end

    it "returns 401 without bearer" do
      get "/api/v1/notification_preferences/org_defaults", as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /api/v1/notification_preferences/org_defaults" do
    # Switching a default off sets the user's own column and every follow row to false
    it "cascades event-type default OFF to all follows" do
      org1 = create(:organization, name: "Mobile Org 1")
      org2 = create(:organization, name: "Mobile Org 2")
      follows = [
        create(:organization_follow, user: user, organization: org1, notify_on_support_change: true),
        create(:organization_follow, user: user, organization: org2, notify_on_support_change: true)
      ]

      headers = authenticate_as(user)
      patch "/api/v1/notification_preferences/org_defaults",
        params: {notify_on_support_change_default: false},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.notify_on_support_change_default).to be false
      follows.each { |f| expect(f.reload.notify_on_support_change).to be false }
    end

    # Switching a default on leaves the follow rows exactly as they were
    it "turning event-type default ON leaves follow values unchanged (asymmetric)" do
      user.update!(notify_on_support_change_default: false)
      org = create(:organization, name: "Mobile Org asymmetric")
      follow = create(:organization_follow, user: user, organization: org, notify_on_support_change: false)

      headers = authenticate_as(user)
      patch "/api/v1/notification_preferences/org_defaults",
        params: {notify_on_support_change_default: true},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      expect(user.reload.notify_on_support_change_default).to be true
      # The follow stays false: turning the default on does not spread
      expect(follow.reload.notify_on_support_change).to be false
    end

    # @lat: [[org-notification-cascade-and-defaults#Why the master toggle checks presence, not truthiness]]
    it "master org_position_taken true->false is applied and does not cascade to follow rows" do
      user.notification_preferences.find_by(key: "org_position_taken").update!(enabled: true)
      org = create(:organization, name: "Mobile Org master gate")
      follow = create(:organization_follow, user: user, organization: org, notify_on_summary_change: true)

      headers = authenticate_as(user)
      patch "/api/v1/notification_preferences/org_defaults",
        params: {org_position_taken: false},
        headers: headers,
        as: :json

      expect(response).to have_http_status(:ok)
      master = user.notification_preferences.reload.find_by(key: "org_position_taken")
      expect(master.enabled).to be false
      expect(follow.reload.notify_on_summary_change).to be true
    end

    it "returns 401 without bearer" do
      patch "/api/v1/notification_preferences/org_defaults",
        params: {notify_on_summary_change_default: false},
        as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
