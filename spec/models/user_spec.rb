require "rails_helper"

RSpec.describe User, type: :model do
  describe "#has_sway_passkey?" do
    it "returns false when the user has no passkeys" do
      user = create(:user)

      expect(user.has_sway_passkey?).to be(false)
    end

    it "returns true when the user has at least one passkey" do
      user = create(:user)
      create(:passkey, user: user)

      expect(user.has_sway_passkey?).to be(true)
    end
  end

  describe "#can_delete_sway_passkeys?" do
    it "returns false when the user only has one passkey" do
      user = create(:user)
      create(:passkey, user: user)

      expect(user.can_delete_sway_passkeys?).to be(false)
    end

    it "returns true when the user has more than one passkey" do
      user = create(:user)
      create(:passkey, user: user)
      create(:passkey, user: user)

      expect(user.can_delete_sway_passkeys?).to be(true)
    end
  end

  describe "webauthn_id initialization" do
    it "assigns a generated webauthn_id on new records" do
      allow(WebAuthn).to receive(:generate_user_id).and_return("generated-webauthn-id")

      user = User.new(phone: "4105557788")

      expect(user.webauthn_id).to eq("generated-webauthn-id")
    end

    it "preserves an explicitly provided webauthn_id" do
      allow(WebAuthn).to receive(:generate_user_id)

      user = User.new(phone: "4105557789", webauthn_id: "existing-id")

      expect(user.webauthn_id).to eq("existing-id")
      expect(WebAuthn).not_to have_received(:generate_user_id)
    end

    it "keeps persisted webauthn_id unchanged on reload" do
      user = User.create!(phone: "4105557790", webauthn_id: "persisted-id")

      expect(user.reload.webauthn_id).to eq("persisted-id")
    end

    it "enforces unique webauthn_id values at the database level" do
      User.create!(phone: "4105557791", webauthn_id: "duplicate-webauthn-id")

      expect do
        User.create!(phone: "4105557792", webauthn_id: "duplicate-webauthn-id")
      end.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end
end
