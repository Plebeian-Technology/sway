# == Schema Information
#
# Table name: api_keys
# Database name: primary
#
#  id               :integer          not null, primary key
#  bearer_type      :string           not null
#  expires_at       :datetime
#  last_used_on_utc :datetime
#  name             :string
#  token_digest     :string           not null
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  bearer_id        :integer          not null
#  user_device_id   :integer
#
# Indexes
#
#  index_api_keys_on_bearer_id_and_bearer_type  (bearer_id,bearer_type)
#  index_api_keys_on_expires_at                 (expires_at)
#  index_api_keys_on_token_digest               (token_digest) UNIQUE
#  index_api_keys_on_user_device_id             (user_device_id)
#
# Foreign Keys
#
#  user_device_id  (user_device_id => user_devices.id)
#
require "rails_helper"

RSpec.describe ApiKey, type: :model do
  describe "associations" do
    it "belongs to a polymorphic bearer (User by default)" do
      record = create(:api_key)
      expect(record).to be_persisted
      expect(record.bearer).to be_a(User)
      expect(record.bearer_type).to eq("User")
    end
  end

  describe "token digest" do
    it "computes a SHA512 HMAC digest on create using the raw token" do
      user = create(:user)
      raw_token = SecureRandom.hex(16)
      expected_digest = OpenSSL::HMAC.hexdigest("SHA512", "test", raw_token)

      record = ApiKey.create!(
        name: "test key",
        token: raw_token,
        bearer: user
      )

      expect(record.token_digest).to eq(expected_digest)
    end

    # @lat: [[api-key-hmac-secret-handling#Why the blank-token spec asserts the exact error class and message]]
    it "refuses to persist when token is blank, naming the attribute" do
      user = create(:user)
      expect { ApiKey.create!(name: "no token", token: nil, bearer: user) }
        .to raise_error(ActiveRecord::RecordInvalid, /Token can't be blank/)
      expect(ApiKey.where(name: "no token")).to be_empty
    end
  end

  # @lat: [[api-key-hmac-secret-handling#Why MissingHmacSecretError is a plain StandardError]]
  # API_KEY_HMAC_SECRET_KEY is not set anywhere yet, so both guards below describe how
  # production behaves today.
  describe "missing API_KEY_HMAC_SECRET_KEY" do
    before do
      allow(ApiKey).to receive(:hmac_secret_key).and_return(nil)
    end

    it "fails .authenticate_by_token! with an error naming the variable" do
      expect { ApiKey.authenticate_by_token!("anything") }
        .to raise_error(ApiKey::MissingHmacSecretError, /API_KEY_HMAC_SECRET_KEY/)
    end

    it "fails creation with an error naming the variable" do
      user = create(:user)

      expect { ApiKey.create!(name: "k", token: SecureRandom.hex(16), bearer: user) }
        .to raise_error(ApiKey::MissingHmacSecretError, /API_KEY_HMAC_SECRET_KEY/)
    end

    # Callers must still be able to tell this apart from "unknown token", which
    # .authenticate_by_token turns into nil. A misconfigured deployment must NOT
    # look like a bad credential.
    it "is not rescued by .authenticate_by_token's RecordNotFound rescue" do
      expect { ApiKey.authenticate_by_token("anything") }
        .to raise_error(ApiKey::MissingHmacSecretError)
    end
  end

  describe ".authenticate_by_token" do
    it "returns the matching record for a known raw token" do
      user = create(:user)
      raw_token = SecureRandom.hex(16)
      record = ApiKey.create!(name: "auth", token: raw_token, bearer: user)

      expect(ApiKey.authenticate_by_token(raw_token)).to eq(record)
    end

    it "returns nil when the token is unknown" do
      expect(ApiKey.authenticate_by_token("does-not-exist")).to be_nil
    end
  end

  describe "#active?" do
    let(:user) { create(:user) }

    it "is true when expires_at is nil and no user_device is associated" do
      key = ApiKey.create!(name: "fresh", token: SecureRandom.hex(16), bearer: user)
      expect(key.active?).to eq(true)
    end

    it "is true when expires_at is in the future" do
      key = ApiKey.create!(
        name: "future",
        token: SecureRandom.hex(16),
        bearer: user,
        expires_at: 1.hour.from_now
      )
      expect(key.active?).to eq(true)
    end

    it "is false when expires_at is in the past" do
      key = ApiKey.create!(
        name: "expired",
        token: SecureRandom.hex(16),
        bearer: user,
        expires_at: 1.hour.ago
      )
      expect(key.active?).to eq(false)
    end

    it "is false when associated user_device is revoked" do
      device = create(:user_device, user: user, revoked_at: Time.current)
      key = ApiKey.create!(
        name: "revoked-device",
        token: SecureRandom.hex(16),
        bearer: user,
        user_device: device
      )
      expect(key.active?).to eq(false)
    end

    it "is true when associated user_device is active and not expired" do
      device = create(:user_device, user: user)
      key = ApiKey.create!(
        name: "ok",
        token: SecureRandom.hex(16),
        bearer: user,
        user_device: device
      )
      expect(key.active?).to eq(true)
    end
  end

  describe ".authenticate_by_token! with expiry/device checks" do
    let(:user) { create(:user) }

    it "raises RecordNotFound for expired tokens" do
      raw_token = SecureRandom.hex(16)
      ApiKey.create!(
        name: "expired",
        token: raw_token,
        bearer: user,
        expires_at: 1.hour.ago
      )

      expect { ApiKey.authenticate_by_token!(raw_token) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "raises RecordNotFound when user_device is revoked" do
      device = create(:user_device, user: user, revoked_at: Time.current)
      raw_token = SecureRandom.hex(16)
      ApiKey.create!(
        name: "revoked",
        token: raw_token,
        bearer: user,
        user_device: device
      )

      expect { ApiKey.authenticate_by_token!(raw_token) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end

    it "returns the api_key when token is valid and device is active" do
      device = create(:user_device, user: user)
      raw_token = SecureRandom.hex(16)
      key = ApiKey.create!(
        name: "valid",
        token: raw_token,
        bearer: user,
        user_device: device
      )

      expect(ApiKey.authenticate_by_token!(raw_token)).to eq(key)
    end

    it "(non-bang) returns nil for expired or device-revoked tokens" do
      device = create(:user_device, user: user, revoked_at: Time.current)
      raw_token = SecureRandom.hex(16)
      ApiKey.create!(
        name: "rev2",
        token: raw_token,
        bearer: user,
        user_device: device
      )

      expect(ApiKey.authenticate_by_token(raw_token)).to be_nil
    end
  end

  describe "User#revoke_all_devices!" do
    it "transactionally revokes every device and expires every linked api_key" do
      user = create(:user)
      device1 = create(:user_device, user: user, push_token: SecureRandom.hex(8))
      device2 = create(:user_device, user: user, push_token: SecureRandom.hex(8))
      key1 = ApiKey.create!(name: "k1", token: SecureRandom.hex(16), bearer: user, user_device: device1)
      key2 = ApiKey.create!(name: "k2", token: SecureRandom.hex(16), bearer: user, user_device: device2)

      user.revoke_all_devices!

      expect(device1.reload.revoked_at).not_to be_nil
      expect(device2.reload.revoked_at).not_to be_nil
      expect(key1.reload.expires_at).not_to be_nil
      expect(key2.reload.expires_at).not_to be_nil
    end
  end
end
