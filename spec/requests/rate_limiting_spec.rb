# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Rate limiting", type: :request do
  # @lat: [[phone-verification-rate-limits#Why spec/requests/rate_limiting_spec.rb stubs Twilio with a double]]
  include_context "TwilioDouble"

  # When a caller is rate-limited, render_rate_limited redirects browser and
  # Inertia clients with a 302, and answers 429 only for JSON clients. The
  # browser examples accept either one.
  def rate_limited_status
    have_http_status(:redirect).or(have_http_status(:too_many_requests))
  end

  describe "POST /users/webauthn/sessions" do
    context "in test env (default)" do
      it "does NOT throttle — 100 requests all proceed past the rate_limit gate" do
        100.times { post "/users/webauthn/sessions", params: {phone: "4105551212"} }
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end

    context "in production with RATE_LIMIT_SIGN_IN_ENABLED=true" do
      it "returns 302/429 after 10 requests from the same IP within 5 minutes" do
        with_rate_limit_enabled(:sign_in) do
          11.times { post "/users/webauthn/sessions", params: {phone: "4105551212"} }
          expect(response).to rate_limited_status
          expect(response.headers["Retry-After"]).to eq("300")
        end
      end

      it "returns 302/429 after 5 requests with the same phone from different IPs" do
        with_rate_limit_enabled(:sign_in) do
          6.times do |i|
            post "/users/webauthn/sessions",
              params: {phone: "4105551212"},
              headers: {"REMOTE_ADDR" => "10.0.0.#{i + 1}"}
          end
          expect(response).to rate_limited_status
          expect(response.headers["Retry-After"]).to eq("300")
        end
      end

      it "buckets a phone by normalized digits, not raw formatting" do
        with_rate_limit_enabled(:sign_in) do
          # @lat: [[phone-verification-rate-limits#Why spec/requests/rate_limiting_spec.rb stubs Twilio with a double]]
          5.times do |i|
            post "/users/webauthn/sessions",
              params: {phone: "+1 (410) 555-1212"},
              headers: {"REMOTE_ADDR" => "10.1.0.#{i + 1}"}
          end
          post "/users/webauthn/sessions",
            params: {phone: "4105551212"},
            headers: {"REMOTE_ADDR" => "10.1.0.6"}
          expect(response).to rate_limited_status
          expect(response.headers["Retry-After"]).to be_present
        end
      end
    end

    context "in production with sign_in_enabled=false (kill switch)" do
      it "does NOT throttle when kill switch is flipped, with a live counting backend wired in" do
        with_rate_limit_disabled(:sign_in) do
          50.times { post "/users/webauthn/sessions", params: {phone: "4105551212"} }
          expect(response).not_to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe "POST /users/webauthn/registration" do
    context "in test env (default)" do
      it "does NOT throttle — 20 requests all proceed past the rate_limit gate" do
        20.times { post "/users/webauthn/registration", params: {phone: "4105551212"} }
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end

    context "in production with RATE_LIMIT_SIGN_UP_ENABLED=true" do
      include_context "SessionDouble"

      around { |example| with_app_config(:webauthn, rp_id: "app.example.test", allowed_origins: "https://app.example.test") { example.run } }

      def verify_phone_in_session(phone)
        session_hash[:phone] = phone
        session_hash[:verified_phone] = phone
        session_hash[:verified_phone_at] = Time.current.to_i
      end

      it "lets six verified phones from one IP start enrollment within 1 hour" do
        with_rate_limit_enabled(:sign_up) do
          6.times do |i|
            verify_phone_in_session("410555#{i.to_s.rjust(4, "0")}")
            post "/users/webauthn/registration", headers: {"REMOTE_ADDR" => "10.0.3.1"}
            expect(response).to have_http_status(:ok)
          end
        end
      end

      it "refuses the 21st start for one verified phone across many IPs with Retry-After 3600" do
        verify_phone_in_session("4105551212")
        with_rate_limit_enabled(:sign_up) do
          20.times do |i|
            post "/users/webauthn/registration", headers: {"REMOTE_ADDR" => "10.0.4.#{i + 1}"}
            expect(response).to have_http_status(:ok)
          end

          post "/users/webauthn/registration", headers: {"REMOTE_ADDR" => "10.0.4.99"}

          expect(response).to rate_limited_status
          expect(response.headers["Retry-After"]).to eq("3600")
        end
      end

      it "refuses the 21st start from one IP whose session has no verified phone" do
        with_rate_limit_enabled(:sign_up) do
          20.times do
            post "/users/webauthn/registration", headers: {"REMOTE_ADDR" => "10.0.5.1"}
            expect(response).to have_http_status(:ok)
          end

          post "/users/webauthn/registration", headers: {"REMOTE_ADDR" => "10.0.5.1"}

          expect(response).to rate_limited_status
          expect(response.headers["Retry-After"]).to eq("3600")
        end
      end
    end

    context "in production with sign_up_enabled=false (kill switch)" do
      around { |example| with_app_config(:webauthn, rp_id: "app.example.test", allowed_origins: "https://app.example.test") { example.run } }

      it "does NOT throttle when kill switch is flipped, with a live counting backend wired in" do
        with_rate_limit_disabled(:sign_up) do
          20.times { post "/users/webauthn/registration", params: {phone: "4105551212"} }
          expect(response).not_to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe "POST /phone_verification" do
    context "in test env (default)" do
      it "does NOT throttle — 20 requests all proceed past the rate_limit gate" do
        20.times do |i|
          post "/phone_verification",
            params: {phone_verification: {phone: "410555#{i.to_s.rjust(4, "0")}"}},
            headers: {"REMOTE_ADDR" => "10.0.0.#{(i % 250) + 1}"}
        end
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end

    context "in production with RATE_LIMIT_PHONE_VERIFY_ENABLED=true" do
      context "when Twilio sends the code" do
        around do |example|
          with_app_config(:dev_login, skip_phone_verification: false) { example.run }
        end

        # @lat: [[phone-verification-rate-limits#Why a one-time code has no per-phone daily cap]]
        it "sends a second code to the same phone from another IP on /phone_verification" do
          with_rate_limit_enabled(:phone_verify) do
            2.times do |i|
              post "/phone_verification",
                params: {phone_verification: {phone: "4105551212"}},
                headers: {"REMOTE_ADDR" => "10.0.0.#{i + 1}"}
              expect(response).to have_http_status(:ok)
            end

            expect(twilio_verifications_double).to have_received(:create).twice
          end
        end

        it "sends a second code to the same phone from another IP on /users/webauthn/sessions" do
          with_rate_limit_enabled(:phone_verify) do
            2.times do |i|
              post "/users/webauthn/sessions",
                params: {phone: "4105551212"},
                headers: {"REMOTE_ADDR" => "10.0.0.#{i + 1}"}
              expect(response).to have_http_status(:ok)
            end

            expect(twilio_verifications_double).to have_received(:create).twice
          end
        end

        it "sends a second code to the same phone from another IP on /api/v1/phone_verification" do
          with_rate_limit_enabled(:phone_verify) do
            2.times do |i|
              post "/api/v1/phone_verification",
                params: {phone: "4105551212"},
                headers: {"REMOTE_ADDR" => "10.0.0.#{i + 1}"},
                as: :json
              expect(response).to have_http_status(:no_content)
            end

            expect(twilio_verifications_double).to have_received(:create).twice
          end
        end

        it "sends a code for the same phone on /users/webauthn/sessions, /phone_verification, and /api/v1/phone_verification" do
          with_rate_limit_enabled(:phone_verify) do
            post "/users/webauthn/sessions",
              params: {phone: "4105559090"},
              headers: {"REMOTE_ADDR" => "10.0.0.10"}
            expect(response).to have_http_status(:ok)

            post "/phone_verification",
              params: {phone_verification: {phone: "4105559090"}},
              headers: {"REMOTE_ADDR" => "10.0.0.11"}
            expect(response).to have_http_status(:ok)

            post "/api/v1/phone_verification",
              params: {phone: "4105559090"},
              headers: {"REMOTE_ADDR" => "10.0.0.12"},
              as: :json
            expect(response).to have_http_status(:no_content)

            expect(twilio_verifications_double).to have_received(:create).exactly(3).times
          end
        end
      end

      it "returns 302/429 after 10 requests from the same IP (per-IP key)" do
        with_rate_limit_enabled(:phone_verify) do
          11.times do |i|
            post "/phone_verification",
              params: {phone_verification: {phone: "410555#{i.to_s.rjust(4, "0")}"}},
              headers: {"REMOTE_ADDR" => "10.0.0.1"}
          end
          expect(response).to rate_limited_status
          expect(response.headers["Retry-After"]).to be_present
        end
      end

      it "answers the 11th JSON code request from one IP with 429 and a one-hour Retry-After" do
        with_rate_limit_enabled(:phone_verify) do
          11.times do |i|
            post "/phone_verification",
              params: {phone_verification: {phone: "410555#{i.to_s.rjust(4, "0")}"}},
              headers: {"REMOTE_ADDR" => "10.0.5.1"},
              as: :json
          end
          expect(response).to have_http_status(:too_many_requests)
          expect(response.headers["Retry-After"]).to eq("3600")
        end
      end

      it "answers the 6th code check for one phone with 429 and a ten-minute Retry-After" do
        with_app_config(:dev_login, skip_phone_verification: false) do
          with_rate_limit_enabled(:phone_verify) do
            post "/phone_verification", params: {phone_verification: {phone: "4105551212"}}, as: :json
            6.times do |i|
              put "/phone_verification/1",
                params: {phone_verification: {code: "000000"}},
                headers: {"REMOTE_ADDR" => "10.0.6.#{i + 1}"},
                as: :json
            end
            expect(response).to have_http_status(:too_many_requests)
            expect(response.headers["Retry-After"]).to eq("600")
          end
        end
      end
    end

    context "in production with phone_verify_enabled=false (kill switch)" do
      it "does NOT throttle when kill switch is flipped, with a live counting backend wired in" do
        with_rate_limit_disabled(:phone_verify) do
          20.times do
            post "/phone_verification",
              params: {phone_verification: {phone: "4105551212"}}
          end
          expect(response).not_to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe "POST /organizations/:organization_id/membership_invites" do
    include_context "SessionDouble"
    include_context "Setup"

    let(:organization) { create(:organization) }

    def make_admin
      _, admin = setup
      create(:user_organization_membership, user: admin, organization: organization, role: :admin)
      session_hash[:user_id] = admin.id
      admin
    end

    # invite_params permits only :invitee_email; the role lives on UserOrganizationMembership
    def invite_post(email, headers = {})
      post organization_membership_invites_path(organization),
        params: {invite: {invitee_email: email}},
        headers: headers
    end

    context "in test env (default)" do
      it "does NOT throttle on repeated invites to the same invitee_email" do
        make_admin
        50.times { invite_post("bomb@example.com") }
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end

    context "in production with RATE_LIMIT_ORG_INVITE_ENABLED=true" do
      it "returns 302/429 + Retry-After after 5 invites to the same invitee_email within 1 hour (per-invitee_email key)" do
        with_rate_limit_enabled(:org_invite) do
          make_admin
          6.times { invite_post("bomb@example.com") }
          expect(response).to rate_limited_status
          expect(response.headers["Retry-After"]).to be_present
        end
      end

      it "returns 302/429 after 30 invites from the same current_user within 1 hour (per-current_user key)" do
        with_rate_limit_enabled(:org_invite) do
          make_admin
          31.times { |i| invite_post("target#{i}@example.com") }
          expect(response).to rate_limited_status
          expect(response.headers["Retry-After"]).to be_present
        end
      end

      it "returns 302/429 after 100 invites from the same IP within 1 hour (per-IP key)" do
        with_rate_limit_enabled(:org_invite) do
          make_admin
          101.times do |i|
            invite_post("t#{i}@example.com", {"REMOTE_ADDR" => "10.0.0.1"})
          end
          expect(response).to rate_limited_status
          expect(response.headers["Retry-After"]).to be_present
        end
      end
    end

    context "in production with org_invite_enabled=false (kill switch)" do
      it "does NOT throttle when kill switch is flipped, with a live counting backend wired in" do
        with_rate_limit_disabled(:org_invite) do
          make_admin
          10.times { invite_post("bomb@example.com") }
          expect(response).not_to have_http_status(:too_many_requests)
        end
      end
    end
  end

  describe "render_rate_limited response shape" do
    it "sets Retry-After header to the sign-in window on HTML request" do
      with_rate_limit_enabled(:sign_in) do
        11.times { post "/users/webauthn/sessions", params: {phone: "4105551212"} }
        expect(response.headers["Retry-After"]).to eq("300")
      end
    end

    it "returns 429 for JSON clients" do
      with_rate_limit_enabled(:sign_in) do
        # Send as JSON body so params parse correctly
        11.times do
          post "/users/webauthn/sessions",
            params: {phone: "4105551212"},
            as: :json
        end
        expect(response).to have_http_status(:too_many_requests)
        expect(response.headers["Retry-After"]).to be_present
      end
    end

    it "redirects for Inertia requests with Retry-After present" do
      with_rate_limit_enabled(:sign_in) do
        11.times do
          post "/users/webauthn/sessions",
            params: {phone: "4105551212"},
            headers: {"X-Inertia" => "true"}
        end
        expect(response).to rate_limited_status
        expect(response.headers["Retry-After"]).to be_present
      end
    end

    it "does not emit Sentry alerts when blocked fewer than REPEATED_BLOCK_THRESHOLD times" do
      memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_cache)
      allow(Sentry).to receive(:capture_message)
      allow(SwayLogging).to receive(:warn)

      with_rate_limit_enabled(:sign_in) do
        6.times do |i|
          post "/users/webauthn/sessions",
            params: {phone: "410555#{i.to_s.rjust(4, "0")}"},
            headers: {"REMOTE_ADDR" => "10.0.0.1"}
        end
        expect(response).to rate_limited_status
        expect(Sentry).not_to have_received(:capture_message)
      end
    end

    it "emits throttled Sentry alerts and SwayLogging warnings when an anonymous IP repeatedly trips rate limits" do
      memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_cache)
      allow(Sentry).to receive(:capture_message)
      allow(SwayLogging).to receive(:warn)

      with_rate_limit_enabled(:sign_in) do
        20.times do |i|
          post "/users/webauthn/sessions",
            params: {phone: "410555#{i.to_s.rjust(4, "0")}"},
            headers: {"REMOTE_ADDR" => "10.0.0.1"}
        end
        expect(response).to rate_limited_status

        expect(Sentry).to have_received(:capture_message).twice.with(
          a_string_matching(%r{\ARepeated rate limit blocks \(ip:10\.0\.0\.1\b}),
          hash_including(level: :warning)
        )
        expect(SwayLogging).to have_received(:warn).at_least(:once).with(
          "rate_limit.repeated_blocks",
          hash_including(actor: "ip:10.0.0.1", count: 5)
        )
      end
    end

    it "resets repeated block counts across REPEATED_BLOCK_WINDOW time buckets" do
      memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_cache)
      allow(Sentry).to receive(:capture_message)

      with_rate_limit_enabled(:sign_in) do
        6.times do |i|
          post "/users/webauthn/sessions",
            params: {phone: "410555#{i.to_s.rjust(4, "0")}"},
            headers: {"REMOTE_ADDR" => "10.0.0.1"}
        end
        expect(Sentry).not_to have_received(:capture_message)

        future_time = Time.current + RateLimitResponder::REPEATED_BLOCK_WINDOW + 1.second
        allow(Time).to receive(:current).and_return(future_time)
        4.times do |i|
          post "/users/webauthn/sessions",
            params: {phone: "410555#{(i + 100).to_s.rjust(4, "0")}"},
            headers: {"REMOTE_ADDR" => "10.0.0.1"}
        end
        expect(Sentry).not_to have_received(:capture_message)
      end
    end

    it "emits Sentry alerts matching actor user:id when an authenticated user repeatedly trips rate limits" do
      memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_cache)
      allow(Sentry).to receive(:capture_message)
      allow(SwayLogging).to receive(:warn)

      user = create(:user, :registered)
      org = create(:organization)
      create(:user_organization_membership, user: user, organization: org, role: :admin)

      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)

      with_rate_limit_enabled(:org_invite) do
        35.times do |i|
          post "/organizations/#{org.id}/membership_invites",
            params: {invite: {invitee_email: "target#{i}@example.com"}}
        end

        expect(response).to rate_limited_status
        expect(Sentry).to have_received(:capture_message).with(
          a_string_matching(%r{\ARepeated rate limit blocks \(user:#{user.id}\b}),
          hash_including(level: :warning)
        )
      end
    end

    it "fails open when Rails.cache.increment raises StandardError" do
      allow(Rails.cache).to receive(:increment).and_raise(StandardError, "Cache connection error")
      allow(Sentry).to receive(:capture_message)

      with_rate_limit_enabled(:sign_in) do
        11.times do |i|
          post "/users/webauthn/sessions",
            params: {phone: "410555#{i.to_s.rjust(4, "0")}"},
            headers: {"REMOTE_ADDR" => "10.0.0.1"}
        end
        expect(response).to rate_limited_status
        expect(response.headers["Retry-After"]).to eq("300")
      end
    end

    it "fails open when Sentry.capture_message raises StandardError" do
      memory_cache = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory_cache)
      allow(Sentry).to receive(:capture_message).and_raise(StandardError, "Sentry transport failure")

      with_rate_limit_enabled(:sign_in) do
        15.times do |i|
          post "/users/webauthn/sessions",
            params: {phone: "410555#{i.to_s.rjust(4, "0")}"},
            headers: {"REMOTE_ADDR" => "10.0.0.1"}
        end
        expect(response).to rate_limited_status
        expect(response.headers["Retry-After"]).to eq("300")
      end
    end
  end

  # @lat: [[identity-and-access#Identity and access#The rate limit store swaps in after boot]]
  describe "production wiring path" do
    it "returns 429 once the backend is wired to Rails.cache like the initializer" do
      memory = ActiveSupport::Cache::MemoryStore.new
      allow(Rails).to receive(:cache).and_return(memory)
      allow(Rails.env).to receive(:production?).and_return(true)

      previous_backend = ApplicationController::RATE_LIMIT_STORE.instance_variable_get(:@backend)
      begin
        ApplicationController::RATE_LIMIT_STORE.backend = Rails.cache

        with_app_config(:rate_limits, sign_in_enabled: true) do
          11.times do
            post "/users/webauthn/sessions", params: {phone: "4105551212"}, as: :json
          end

          expect(response).to have_http_status(:too_many_requests)
          expect(response.headers["Retry-After"]).to be_present
        end
      ensure
        ApplicationController::RATE_LIMIT_STORE.backend = previous_backend
      end
    end
  end
end
