# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db", "data", "20261110000001_rename_botw_announcement_preferences_to_botm")

RSpec.describe "RenameBotwAnnouncementPreferencesToBotm data migration", type: :model do
  let(:migration) { Object.const_get(:RenameBotwAnnouncementPreferencesToBotm).new }
  let(:user) { create(:user) }

  def insert_preference(key, enabled, for_user: user)
    NotificationPreference.insert!({user_id: for_user.id, key:, enabled:})
    NotificationPreference.find_by!(user_id: for_user.id, key:)
  end

  def run_rename
    ActiveRecord::Migration.suppress_messages { migration.up }
  end

  it "renames a lone botw_announcement row and keeps its enabled value" do
    other_user = create(:user)
    enabled_row = insert_preference("botw_announcement", true)
    disabled_row = insert_preference("botw_announcement", false, for_user: other_user)

    run_rename

    expect(enabled_row.reload).to have_attributes(key: "botm_announcement", enabled: true)
    expect(disabled_row.reload).to have_attributes(key: "botm_announcement", enabled: false)
  end

  it "deletes the botw_announcement row of a pair and leaves its botm_announcement row unchanged" do
    botw_row = insert_preference("botw_announcement", true)
    botm_row = insert_preference("botm_announcement", false)
    botm_attributes = botm_row.attributes

    run_rename

    expect(NotificationPreference.exists?(botw_row.id)).to be(false)
    expect(botm_row.reload.attributes).to eq(botm_attributes)
  end

  it "leaves a lone botm_announcement row and other keys alone" do
    botm_row = insert_preference("botm_announcement", false)
    other_row = insert_preference("legislator_voted", true)
    unchanged = [botm_row, other_row].map(&:attributes)

    run_rename

    expect([botm_row, other_row].map { |row| row.reload.attributes }).to eq(unchanged)
  end

  it "can run twice" do
    insert_preference("botw_announcement", false)

    run_rename
    expect { run_rename }.not_to change { NotificationPreference.pluck(:user_id, :key, :enabled) }

    expect(NotificationPreference.where(user_id: user.id).pluck(:key, :enabled)).to eq([["botm_announcement", false]])
  end
end
