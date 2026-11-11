require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  include_context "Setup"

  let(:user) { setup.last }

  describe "#connect" do
    it "identifies current_user from the session[:user_id]" do
      connect session: {user_id: user.id}
      expect(connection.current_user).to eq(user)
    end

    it "identifies current_user when session[:auth_identity] matches user.created_at.to_i" do
      connect session: {user_id: user.id, auth_identity: user.created_at.to_i}
      expect(connection.current_user).to eq(user)
    end

    it "rejects the connection when session[:auth_identity] does not match user.created_at.to_i" do
      expect {
        connect session: {user_id: user.id, auth_identity: user.created_at.to_i - 60}
      }.to have_rejected_connection
    end

    context "bearer token query param fallback (mobile WebSocket)" do
      it "identifies current_user from a valid active Bearer token" do
        raw_token = SecureRandom.hex(16)
        device = create(:user_device, user: user)
        ApiKey.create!(name: "mobile-ws", token: raw_token, bearer: user, user_device: device)

        connect "/cable?token=#{raw_token}"
        expect(connection.current_user).to eq(user)
      end

      it "rejects an expired Bearer token" do
        raw_token = SecureRandom.hex(16)
        ApiKey.create!(name: "expired-ws", token: raw_token, bearer: user, expires_at: 1.minute.ago)

        expect { connect "/cable?token=#{raw_token}" }.to have_rejected_connection
      end

      it "rejects a Bearer token whose user_device has been revoked" do
        raw_token = SecureRandom.hex(16)
        device = create(:user_device, user: user, revoked_at: Time.current)
        ApiKey.create!(name: "revoked-ws", token: raw_token, bearer: user, user_device: device)

        expect { connect "/cable?token=#{raw_token}" }.to have_rejected_connection
      end
    end

    # @lat: [[action-cable-connection-refresh-token-fallback#How the spec exercises the fallback]]
    context "encrypted refresh_token cookie fallback (in lockstep with HTTP auth)" do
      it "rejects an expired refresh token over cable" do
        rt = RefreshToken.create!(
          user: user,
          token: "expired-token",
          ip_address: "0.0.0.0",
          user_agent: "Rails Testing",
          expires_at: 1.minute.ago
        )
        allow_any_instance_of(ApplicationCable::Connection)
          .to receive(:cookies)
          .and_return(double(encrypted: {refresh_token: rt.token}))

        expect { connect }.to have_rejected_connection
      end

      it "rejects a refresh token presented from a different IP/UA" do
        rt = RefreshToken.create!(
          user: user,
          token: "mismatched-token",
          ip_address: "203.0.113.1",
          user_agent: "SomeOtherAgent/1.0",
          expires_at: 1.year.from_now
        )
        allow_any_instance_of(ApplicationCable::Connection)
          .to receive(:cookies)
          .and_return(double(encrypted: {refresh_token: rt.token}))

        expect { connect }.to have_rejected_connection
      end

      it "accepts a valid refresh token matching ip/ua/expiry" do
        rt = RefreshToken.create!(
          user: user,
          token: "valid-token",
          ip_address: "0.0.0.0",
          user_agent: "Rails Testing",
          expires_at: 1.year.from_now
        )
        allow_any_instance_of(ApplicationCable::Connection)
          .to receive(:cookies)
          .and_return(double(encrypted: {refresh_token: rt.token}))

        connect
        expect(connection.current_user).to eq(user)
      end
    end

    it "rejects the connection when there is no session and no refresh_token cookie" do
      expect { connect }.to have_rejected_connection
    end

    it "rejects the connection when session[:user_id] points to a missing user" do
      expect { connect session: {user_id: 0} }.to have_rejected_connection
    end
  end
end
