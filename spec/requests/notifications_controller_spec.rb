# frozen_string_literal: true

require "rails_helper"

RSpec.describe "NotificationsController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  describe "PATCH /notifications/settings" do
    it "updates sms_notifications_enabled" do
      sway_locale, user = setup

      patch settings_notifications_path,
            params: {
              user: {
                sms_notifications_enabled: true,
              },
            }
      expect(response).to have_http_status(:found)
      expect(user.reload.sms_notifications_enabled).to be true
      expect(response).to redirect_to(notifications_path)
    end

    it "disables sms_notifications_enabled" do
      sway_locale, user = setup
      user.update(sms_notifications_enabled: true)

      patch settings_notifications_path,
            params: {
              user: {
                sms_notifications_enabled: false,
              },
            }
      expect(response).to have_http_status(:found)
      expect(user.reload.sms_notifications_enabled).to be false
      expect(response).to redirect_to(notifications_path)
    end
  end
end
