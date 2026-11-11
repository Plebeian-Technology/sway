# == Schema Information
#
# Table name: passkeys
# Database name: primary
#
#  id           :integer          not null, primary key
#  aaguid       :string
#  label        :string           not null
#  last_used_at :datetime
#  public_key   :string
#  sign_count   :integer
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  external_id  :string
#  user_id      :integer          not null
#
# Indexes
#
#  index_passkeys_on_external_id        (external_id) UNIQUE
#  index_passkeys_on_public_key         (public_key) UNIQUE
#  index_passkeys_on_user_id            (user_id)
#  index_passkeys_on_user_id_and_label  (user_id,label) UNIQUE
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
require "rails_helper"

RSpec.describe Passkey, type: :model do
  subject(:passkey) { build(:passkey) }

  it "is valid with all attributes" do
    expect(passkey).to be_valid
  end

  it "is invalid without external_id" do
    passkey.external_id = nil

    expect(passkey).to be_invalid
    expect(passkey.errors[:external_id]).to include("can't be blank")
  end

  it "is invalid without public_key" do
    passkey.public_key = nil

    expect(passkey).to be_invalid
    expect(passkey.errors[:public_key]).to include("can't be blank")
  end

  it "is invalid without label" do
    passkey.label = nil

    expect(passkey).to be_invalid
    expect(passkey.errors[:label]).to include("can't be blank")
  end

  it "is invalid without sign_count" do
    passkey.sign_count = nil

    expect(passkey).to be_invalid
    expect(passkey.errors[:sign_count]).to include("can't be blank")
  end

  it "is invalid with duplicate external_id" do
    create(:passkey, external_id: passkey.external_id)

    expect(passkey).to be_invalid
    expect(passkey.errors[:external_id]).to include("has already been taken")
  end

  # @lat: [[identity-and-access#A passkey label is unique to its owner, not to the system]]
  it "is invalid with a duplicate label for the same user" do
    user = create(:user)
    create(:passkey, user: user, label: "iPhone")
    duplicate = build(:passkey, user: user, label: "iPhone")

    expect(duplicate).to be_invalid
    expect(duplicate.errors[:label]).to include("has already been taken")
  end

  it "allows the same label for a different user" do
    create(:passkey, user: create(:user), label: "iPhone")
    other = build(:passkey, user: create(:user), label: "iPhone")

    expect(other).to be_valid
  end

  it "is invalid with negative sign_count" do
    passkey.sign_count = -1

    expect(passkey).to be_invalid
    expect(passkey.errors[:sign_count]).to include(
      "must be greater than or equal to 0"
    )
  end

  it "is invalid with sign_count above 2^32 - 1" do
    passkey.sign_count = 4_294_967_296

    expect(passkey).to be_invalid
    expect(passkey.errors[:sign_count]).to include(
      "must be less than or equal to 4294967295"
    )
  end

  it "belongs to user" do
    expect(passkey.user).to be_present
  end

  describe "#device_name" do
    it "resolves a known AAGUID to its friendly authenticator name" do
      passkey.aaguid = "dd4ec289-e01d-41c9-bb89-70fa845d4bf2"

      expect(passkey.device_name).to eq("iCloud Keychain (Managed)")
    end

    it "returns nil when AAGUID is missing (rows stored before AAGUID capture)" do
      passkey.aaguid = nil

      expect(passkey.device_name).to be_nil
    end

    it "returns nil for the all-zeros AAGUID (privacy-mode authenticators)" do
      passkey.aaguid = "00000000-0000-0000-0000-000000000000"

      expect(passkey.device_name).to be_nil
    end

    it "returns nil for unknown AAGUIDs not in the curated registry" do
      passkey.aaguid = "deadbeef-dead-beef-dead-beefdeadbeef"

      expect(passkey.device_name).to be_nil
    end
  end
end
