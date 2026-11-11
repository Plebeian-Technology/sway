# == Schema Information
#
# Table name: refresh_tokens
# Database name: primary
#
#  id         :integer          not null, primary key
#  expires_at :datetime         not null
#  ip_address :string           not null
#  token      :string           not null
#  user_agent :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  user_id    :integer          not null
#
# Indexes
#
#  index_refresh_tokens_on_token    (token) UNIQUE
#  index_refresh_tokens_on_user_id  (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
require "rails_helper"

RSpec.describe RefreshToken, type: :model do
  let(:user) { create(:user) }
  let(:request) do
    instance_double(
      ActionDispatch::Request,
      remote_ip: "203.0.113.10",
      user_agent: "RSpec Browser"
    )
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
      existing =
        create(
          :refresh_token,
          user: user,
          ip_address: "198.51.100.1",
          user_agent: "Old Agent"
        )

      replacement = described_class.for(user, request)

      expect { existing.reload }.to raise_error(ActiveRecord::RecordNotFound)
      expect(replacement.id).not_to eq(existing.id)
      expect(user.reload.refresh_token).to eq(replacement)
    end

    # Issuing a fresh token deletes every row for that user_id, not only the one row the
    # has_one association knows about, and does it inside a transaction. So a user who
    # somehow ended up with several tokens — two requests rotating at the same moment,
    # say — is left with exactly one.
    it "leaves exactly one token when the user has multiple rows" do
      # Two rows for one user, bypassing the has_one association.
      RefreshToken.create!(user_id: user.id, ip_address: "198.51.100.1", user_agent: "A",
        token: SecureRandom.urlsafe_base64(32), expires_at: 1.year.from_now)
      RefreshToken.create!(user_id: user.id, ip_address: "198.51.100.2", user_agent: "B",
        token: SecureRandom.urlsafe_base64(32), expires_at: 1.year.from_now)
      expect(RefreshToken.where(user_id: user.id).count).to eq(2)

      described_class.for(user, request)

      expect(RefreshToken.where(user_id: user.id).count).to eq(1)
    end

    it "rolls back and keeps the old token when create! fails mid-rotation" do
      existing = create(:refresh_token, user: user)
      allow(RefreshToken).to receive(:create!).and_raise(ActiveRecord::RecordNotUnique, "boom")

      expect { described_class.for(user, request) }.to raise_error(ActiveRecord::RecordNotUnique)

      # The delete was undone along with the failed create, so the old token survives.
      expect(RefreshToken.where(user_id: user.id).pluck(:id)).to eq([existing.id])
    end
  end

  describe "#expired?" do
    it "returns true when expires_at is in the past" do
      refresh_token =
        create(:refresh_token, user: user, expires_at: 1.minute.ago)

      expect(refresh_token.expired?).to be(true)
    end

    it "returns false when expires_at is in the future" do
      refresh_token =
        create(:refresh_token, user: user, expires_at: 1.minute.from_now)

      expect(refresh_token.expired?).to be(false)
    end
  end

  describe "#usable_for?" do
    let(:refresh_token) do
      create(
        :refresh_token,
        user: user,
        ip_address: "203.0.113.10",
        user_agent: "RSpec Browser",
        expires_at: 1.day.from_now
      )
    end

    it "returns true when token is unexpired and request metadata matches" do
      expect(refresh_token.usable_for?(request)).to be(true)
    end

    it "returns false when request ip does not match" do
      invalid_request =
        instance_double(
          ActionDispatch::Request,
          remote_ip: "203.0.113.11",
          user_agent: "RSpec Browser"
        )

      expect(refresh_token.usable_for?(invalid_request)).to be(false)
    end

    it "returns false when request user_agent does not match" do
      invalid_request =
        instance_double(
          ActionDispatch::Request,
          remote_ip: "203.0.113.10",
          user_agent: "Another Browser"
        )

      expect(refresh_token.usable_for?(invalid_request)).to be(false)
    end

    it "returns false when token is expired" do
      refresh_token.update!(expires_at: 1.minute.ago)

      expect(refresh_token.usable_for?(request)).to be(false)
    end
  end

  describe "#as_cookie" do
    let(:refresh_token) do
      create(:refresh_token, user: user, token: "cookie-token")
    end

    it "returns expected cookie attributes" do
      cookie = refresh_token.as_cookie

      expect(cookie[:value]).to eq("cookie-token")
      expect(cookie[:httponly]).to be(true)
      expect(cookie[:same_site]).to eq("Strict")
      expect(cookie[:secure]).to be(false)
      expect(cookie[:expires]).to be_within(2.seconds).of(
        RefreshToken.expires_at
      )
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

  describe "encryption at rest" do
    it "encrypts ip_address in the raw database column while keeping usable_for? transparent" do
      rt = create(
        :refresh_token,
        user: user,
        ip_address: "203.0.113.42",
        user_agent: "RSpec Browser",
        expires_at: 1.day.from_now
      )

      raw_ip = ActiveRecord::Base.connection.select_value(
        "SELECT ip_address FROM refresh_tokens WHERE id = #{rt.id}"
      )
      expect(raw_ip).to be_present
      expect(raw_ip).not_to eq("203.0.113.42")
      expect(rt.reload.ip_address).to eq("203.0.113.42")

      matching_req = instance_double(
        ActionDispatch::Request,
        remote_ip: "203.0.113.42",
        user_agent: "RSpec Browser"
      )
      expect(rt.usable_for?(matching_req)).to be(true)
    end
  end
end
