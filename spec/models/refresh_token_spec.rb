require "rails_helper"

RSpec.describe RefreshToken, type: :model do
  let(:user) { create(:user) }
  let(:request) do
    instance_double(ActionDispatch::Request, remote_ip: "203.0.113.10", user_agent: "RSpec Browser")
  end

  describe ".for" do
    it "creates a refresh token tied to request metadata" do
      token = described_class.for(user, request)

      expect(token.user).to eq(user)
      expect(token.ip_address).to eq("203.0.113.10")
      expect(token.user_agent).to eq("RSpec Browser")
      expect(token.token).to be_present
      expect(token.expires_at).to be > Time.zone.now
    end

    it "replaces an existing refresh token for the same user" do
      existing = create(
        :refresh_token,
        user: user,
        ip_address: "198.51.100.1",
        user_agent: "Old Agent",
      )

      replacement = described_class.for(user, request)

      expect { existing.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(replacement.id).not_to eq(existing.id)
      expect(user.reload.refresh_token).to eq(replacement)
    end
  end

  describe "#expired?" do
    it "returns true when expires_at is in the past" do
      refresh_token = create(:refresh_token, user: user, expires_at: 1.minute.ago)

      expect(refresh_token.expired?).to be(true)
    end

    it "returns false when expires_at is in the future" do
      refresh_token = create(:refresh_token, user: user, expires_at: 1.minute.from_now)

      expect(refresh_token.expired?).to be(false)
    end
  end

  describe "#is_valid?" do
    let(:refresh_token) do
      create(
        :refresh_token,
        user: user,
        ip_address: "203.0.113.10",
        user_agent: "RSpec Browser",
        expires_at: 1.day.from_now,
      )
    end

    it "returns true when token is unexpired and request metadata matches" do
      expect(refresh_token.is_valid?(request)).to be(true)
    end

    it "returns false when request ip does not match" do
      invalid_request = instance_double(
        ActionDispatch::Request,
        remote_ip: "203.0.113.11",
        user_agent: "RSpec Browser",
      )

      expect(refresh_token.is_valid?(invalid_request)).to be(false)
    end

    it "returns false when request user_agent does not match" do
      invalid_request = instance_double(
        ActionDispatch::Request,
        remote_ip: "203.0.113.10",
        user_agent: "Another Browser",
      )

      expect(refresh_token.is_valid?(invalid_request)).to be(false)
    end

    it "returns false when token is expired" do
      refresh_token.update!(expires_at: 1.minute.ago)

      expect(refresh_token.is_valid?(request)).to be(false)
    end
  end

  describe "#as_cookie" do
    let(:refresh_token) { create(:refresh_token, user: user, token: "cookie-token") }

    it "returns expected cookie attributes" do
      cookie = refresh_token.as_cookie

      expect(cookie[:value]).to eq("cookie-token")
      expect(cookie[:httponly]).to be(true)
      expect(cookie[:same_site]).to eq("Strict")
      expect(cookie[:secure]).to be(false)
      expect(cookie[:expires]).to be_within(2.seconds).of(RefreshToken.expires_at)
    end

    it "sets secure when in production" do
      allow(Rails.env).to receive(:production?).and_return(true)

      expect(refresh_token.as_cookie[:secure]).to be(true)
    end
  end

  describe "uniqueness" do
    it "enforces unique token values at the database level" do
      create(:refresh_token, token: "duplicate-token")

      expect do
        create(:refresh_token, token: "duplicate-token")
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
