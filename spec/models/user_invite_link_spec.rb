# == Schema Information
#
# Table name: user_invite_links
# Database name: primary
#
#  id          :integer          not null, primary key
#  invite_uuid :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :integer          not null
#
# Indexes
#
#  index_user_invite_links_on_invite_uuid  (invite_uuid) UNIQUE
#  index_user_invite_links_on_user_id      (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
require "rails_helper"

RSpec.describe UserInviteLink, type: :model do
  describe "associations" do
    it "persists with a user via the :user_invite_link factory" do
      record = create(:user_invite_link)
      expect(record).to be_persisted
      expect(record.user).to be_a(User)
    end
  end

  describe "invite_uuid" do
    it "auto-generates a UUID on create" do
      record = create(:user_invite_link)
      expect(record.invite_uuid).to be_present
      expect(record.invite_uuid).to match(/\A[0-9a-f-]{36}\z/)
    end

    it "generates distinct UUIDs across multiple invite links" do
      first = create(:user_invite_link)
      second = create(:user_invite_link)
      expect(first.invite_uuid).not_to eq(second.invite_uuid)
    end
  end

  describe ".from" do
    it "creates a UserInviteLink for the given user" do
      user = create(:user)
      expect { described_class.from(user: user) }
        .to change(UserInviteLink, :count).by(1)
    end
  end
end
