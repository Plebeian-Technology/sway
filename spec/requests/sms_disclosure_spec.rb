# frozen_string_literal: true

require "rails_helper"

# @lat: [[public-disclosure-pages#Why /sms renders the live consent panel instead of a screenshot]]
RSpec.describe "SmsDisclosure", type: :request do
  describe "GET /sms" do
    context "as an unauthenticated visitor" do
      it "returns 200" do
        get "/sms"

        expect(response).to have_http_status(:ok)
      end

      it "does not redirect to login or root" do
        get "/sms"

        expect(response).not_to be_redirect
      end

      it "renders the Sms page component" do
        get "/sms"

        expect(inertia).to render_component(Pages::SMS)
      end

      it "passes the Twilio sending number as the sms_phone prop" do
        with_env("TWILIO_FROM_PHONE" => "+14105550123") do
          get "/sms"

          expect(inertia).to have_props(sms_phone: "(410) 555-0123")
        end
      end

      it "passes a nil sms_phone prop when no sending number is configured" do
        with_env("TWILIO_FROM_PHONE" => nil) do
          get "/sms"

          expect(inertia).to have_props(sms_phone: nil)
        end
      end

      it "renders under the public entrypoint, not the authenticated app bundle" do
        get "/sms"

        expect(response.body).to match(%r{/assets/public-[^"']+\.js})
        expect(response.body).not_to match(%r{/assets/application-[^"']+\.js})
      end
    end

    context "as an authenticated user" do
      it "still returns 200 (page is open to everyone)" do
        get "/sms"

        expect(response).to have_http_status(:ok)
      end
    end
  end
end
