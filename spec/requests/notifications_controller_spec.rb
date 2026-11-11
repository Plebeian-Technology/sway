# frozen_string_literal: true

require "rails_helper"

RSpec.describe "NotificationsController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  # Send the X-Inertia header on GETs so the response comes back as JSON rather
  # than the HTML layout, which would need Vite-built assets that are not
  # available here. Same approach as
  # pipeline_activity_logger_inertia_flash_spec.rb.
  let(:inertia_headers) do
    {
      "X-Inertia" => "true",
      "X-Inertia-Version" => InertiaRails.configuration.version.to_s
    }
  end

  describe "GET /notifications" do
    it "renders the Notifications component" do
      _sway_locale, _user = setup

      get notifications_path, headers: inertia_headers

      expect(inertia).to render_component Pages::NOTIFICATIONS
    end

    it "defers the subscriptions prop" do
      _sway_locale, _user = setup

      get notifications_path, headers: inertia_headers

      expect(inertia).to have_deferred_props(:subscriptions)
    end

    # @lat: [[push-notification-subscription-design#Why to_builder withholds auth and p256dh]]
    it "does not expose VAPID auth/p256dh secrets on deferred subscriptions" do
      _sway_locale, user = setup
      create(
        :push_notification_subscription,
        user: user,
        endpoint: "https://fcm.googleapis.com/fcm/send/abc",
        auth: "secret-auth-token",
        p256dh: "secret-p256dh-key"
      )

      get notifications_path, headers: inertia_headers
      inertia_load_deferred_props

      subs = inertia.props[:subscriptions].to_a
      expect(subs.length).to eq(1)
      sub = subs.first
      expect(sub).not_to have_key("auth")
      expect(sub).not_to have_key(:auth)
      expect(sub).not_to have_key("p256dh")
      expect(sub).not_to have_key(:p256dh)
      expect(sub["endpoint"]).to eq("https://fcm.googleapis.com/fcm/send/abc")
    end

    it "passes the sms_notifications_enabled prop" do
      _sway_locale, user = setup

      get notifications_path, headers: inertia_headers

      expect(inertia).to have_props(
        sms_notifications_enabled: user.sms_notifications_enabled
      )
    end

    # @lat: [[sms-notification-service-design#Where the displayed Sway number comes from]]
    it "shows the Twilio sending number as the sms_phone prop" do
      with_env("TWILIO_FROM_PHONE" => "+14105550123") do
        setup

        get notifications_path, headers: inertia_headers

        expect(inertia).to have_props(sms_phone: "(410) 555-0123")
      end
    end

    it "passes a nil sms_phone prop when no sending number is configured" do
      with_env("TWILIO_FROM_PHONE" => nil) do
        setup

        get notifications_path, headers: inertia_headers

        expect(inertia).to have_props(sms_phone: nil)
      end
    end

    # The account-wide organization settings are passed to the page as props.
    it "surfaces the global org tier (master + cadence + 3 event-type defaults) as props" do
      _sway_locale, user = setup
      NotificationPreference.seed_defaults_for(user)
      user.update!(
        org_position_cadence_default: :daily,
        notify_on_new_position_default: true,
        notify_on_support_change_default: false,
        notify_on_summary_change_default: true
      )
      user.notification_preferences.find_by(key: "org_position_taken").update!(enabled: false)

      get notifications_path, headers: inertia_headers

      expect(inertia).to have_props(
        org_position_taken: false,
        org_position_cadence_default: "daily",
        notify_on_new_position_default: true,
        notify_on_support_change_default: false,
        notify_on_summary_change_default: true
      )
    end
  end

  describe "PATCH /notifications/settings" do
    it "updates sms_notifications_enabled" do
      _, user = setup

      patch settings_notifications_path,
        params: {
          user: {
            sms_notifications_enabled: true
          }
        }
      expect(response).to have_http_status(:found)
      expect(user.reload.sms_notifications_enabled).to be true
      expect(response).to redirect_to(notifications_path(tab: "sms"))
    end

    it "disables sms_notifications_enabled" do
      _, user = setup
      user.update(sms_notifications_enabled: true)

      patch settings_notifications_path,
        params: {
          user: {
            sms_notifications_enabled: false
          }
        }
      expect(response).to have_http_status(:found)
      expect(user.reload.sms_notifications_enabled).to be false
      expect(response).to redirect_to(notifications_path(tab: "sms"))
    end
  end

  describe "PATCH /notifications/org_defaults" do
    # A request with nobody signed in is refused; browsers go back to the root.
    it "rejects unauthenticated request (redirects to root)" do
      patch org_defaults_notifications_path,
        params: {user: {notify_on_summary_change_default: false}}

      expect(response).to redirect_to(root_url)
    end

    # Turning a setting OFF cascades: the user's column and every follow go false
    it "cascades event-type OFF to all follows" do
      _sway_locale, user = setup
      org1 = create(:organization, name: "Org cascade 1")
      org2 = create(:organization, name: "Org cascade 2")
      org3 = create(:organization, name: "Org cascade 3")
      follows = [
        create(:organization_follow, user: user, organization: org1, notify_on_summary_change: true),
        create(:organization_follow, user: user, organization: org2, notify_on_summary_change: true),
        create(:organization_follow, user: user, organization: org3, notify_on_summary_change: true)
      ]

      patch org_defaults_notifications_path,
        params: {user: {notify_on_summary_change_default: "false"}}

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(notifications_path(tab: "organizations"))
      expect(user.reload.notify_on_summary_change_default).to be false
      follows.each { |f| expect(f.reload.notify_on_summary_change).to be false }
    end

    it "turning event-type ON leaves follow values unchanged (asymmetric)" do
      _sway_locale, user = setup
      user.update!(notify_on_summary_change_default: false)
      org = create(:organization, name: "Org asymmetric")
      follow = create(:organization_follow, user: user, organization: org, notify_on_summary_change: false)

      patch org_defaults_notifications_path,
        params: {user: {notify_on_summary_change_default: "true"}}

      expect(response).to have_http_status(:found)
      expect(user.reload.notify_on_summary_change_default).to be true
      expect(follow.reload.notify_on_summary_change).to be false
    end

    # @lat: [[org-notification-cascade-and-defaults#Why the master toggle checks presence, not truthiness]]
    it "master org_position_taken true->false is applied and does not cascade to follow rows" do
      _sway_locale, user = setup
      NotificationPreference.seed_defaults_for(user)
      user.notification_preferences.find_by(key: "org_position_taken").update!(enabled: true)
      org = create(:organization, name: "Org master gate")
      follow = create(:organization_follow, user: user, organization: org, notify_on_summary_change: true)

      patch org_defaults_notifications_path,
        params: {user: {org_position_taken: false}}, as: :json

      expect(response).to have_http_status(:found)
      master_pref = user.notification_preferences.reload.find_by(key: "org_position_taken")
      expect(master_pref.enabled).to be false
      expect(follow.reload.notify_on_summary_change).to be true
    end

    # On success it redirects after the write, so a refresh cannot resubmit
    it "is a PRG redirect (web) and persists org defaults" do
      _sway_locale, user = setup

      patch org_defaults_notifications_path,
        params: {user: {org_position_cadence_default: "weekly"}}

      expect(response).to have_http_status(:found)
      expect(response).to redirect_to(notifications_path(tab: "organizations"))
      expect(user.reload.org_position_cadence_default).to eq("weekly")
    end
  end

  # @lat: [[tab-preserving-redirect-and-stale-element-lookups#Why every NotificationsController redirect names its tab explicitly]]
  describe "the tab a save returns to" do
    it "keeps the SMS tab open after saving SMS settings" do
      setup

      patch settings_notifications_path, params: {user: {sms_notifications_enabled: true}}

      expect(response).to redirect_to(notifications_path(tab: "sms"))
    end

    it "keeps the SMS tab open when the save is refused" do
      _, user = setup
      allow_any_instance_of(User).to receive(:update).and_return(false)
      allow_any_instance_of(User).to receive(:errors).and_return(user.errors)

      patch settings_notifications_path, params: {user: {sms_notifications_enabled: true}}

      expect(response).to redirect_to(notifications_path(tab: "sms"))
    end

    it "keeps the Organizations tab open after saving org defaults" do
      setup

      patch org_defaults_notifications_path,
        params: {user: {org_position_cadence_default: "daily"}}

      expect(response).to redirect_to(notifications_path(tab: "organizations"))
    end

    it "keeps the Organizations tab open when the save is refused" do
      _, user = setup
      allow_any_instance_of(User).to receive(:update).and_return(false)
      allow_any_instance_of(User).to receive(:errors).and_return(user.errors)

      patch org_defaults_notifications_path,
        params: {user: {org_position_cadence_default: "daily"}}

      expect(response).to redirect_to(notifications_path(tab: "organizations"))
    end
  end
end
