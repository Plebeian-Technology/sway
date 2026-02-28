# == Schema Information
#
# Table name: passkeys
# Database name: primary
#
#  id           :integer          not null, primary key
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
#  index_passkeys_on_external_id  (external_id) UNIQUE
#  index_passkeys_on_public_key   (public_key) UNIQUE
#  index_passkeys_on_user_id      (user_id)
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

  it "is invalid with negative sign_count" do
    passkey.sign_count = -1

    expect(passkey).to be_invalid
    expect(passkey.errors[:sign_count]).to include(
      "must be greater than or equal to 0",
    )
  end

  it "is invalid with sign_count above 2^32 - 1" do
    passkey.sign_count = 4_294_967_296

    expect(passkey).to be_invalid
    expect(passkey.errors[:sign_count]).to include(
      "must be less than or equal to 4294967295",
    )
  end

  it "belongs to user" do
    expect(passkey.user).to be_present
  end
end
