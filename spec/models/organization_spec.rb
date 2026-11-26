# frozen_string_literal: true

# == Schema Information
#
# Table name: organizations
# Database name: primary
#
#  id             :integer          not null, primary key
#  icon_url       :string
#  name           :string           not null
#  created_at     :datetime         not null
#  updated_at     :datetime         not null
#  sway_locale_id :integer          not null
#
# Indexes
#
#  index_organizations_on_name_and_sway_locale_id  (name,sway_locale_id) UNIQUE
#  index_organizations_on_sway_locale_id           (sway_locale_id)
#
# Foreign Keys
#
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
require "rails_helper"

RSpec.describe Organization, type: :model do
  describe "associations" do
    it "belongs to a sway_locale" do
      record = create(:organization)
      expect(record.sway_locale).to be_a(SwayLocale)
    end

    it "has many organization_bill_positions" do
      org = create(:organization)
      bill = create(:bill, sway_locale: org.sway_locale)
      position =
        create(:organization_bill_position, organization: org, bill: bill)
      expect(org.positions).to include(position)
    end

    it "has many bills through positions" do
      org = create(:organization)
      bill = create(:bill, sway_locale: org.sway_locale)
      create(:organization_bill_position, organization: org, bill: bill)
      expect(org.bills).to include(bill)
    end
  end

  describe "validations" do
    it "is valid with a factory-built instance" do
      expect(create(:organization)).to be_valid
    end

    it "enforces uniqueness of name scoped to sway_locale_id" do
      sway_locale = create(:sway_locale)
      create(:organization, name: "Dup Org", sway_locale: sway_locale)
      dup = build(:organization, name: "Dup Org", sway_locale: sway_locale)
      expect(dup.valid?).to be(false)
      expect(dup.errors[:name]).to be_present
    end

    it "permits same name across different sway_locales" do
      locale1 = create(:sway_locale, city: "City1", state: "maryland", country: "united_states")
      locale2 = create(:sway_locale, city: "City2", state: "maryland", country: "united_states")
      create(:organization, name: "Shared", sway_locale: locale1)
      other = build(:organization, name: "Shared", sway_locale: locale2)
      expect(other.valid?).to be(true)
    end
  end

  describe "#to_public_json" do
    it "sends no follower count" do
      expect(create(:organization).to_public_json).not_to have_key(:follower_count)
    end
  end

  # Who actually gets notified. Followers who muted a change type drop out. Active members
  # with no follow row of their own fall back to their user-level defaults.
  describe "#notifiable_follower_set_for" do
    let(:org) { create(:organization) }

    it "excludes a follower whose notify_on_support_change is false for [:support_change]" do
      muted_user = create(:user)
      create(:organization_follow, user: muted_user, organization: org,
        notify_on_support_change: false, notify_on_new_position: true, notify_on_summary_change: true)

      result_ids = org.notifiable_follower_set_for([:support_change]).map(&:first)
      expect(result_ids).not_to include(muted_user.id)
    end

    it "includes a follower with notify_on_support_change true for [:support_change]" do
      enabled_user = create(:user)
      create(:organization_follow, user: enabled_user, organization: org,
        notify_on_support_change: true)

      result_ids = org.notifiable_follower_set_for([:support_change]).map(&:first)
      expect(result_ids).to include(enabled_user.id)
    end

    it "includes an active member with no follow row when global default is true" do
      member_user = create(:user, notify_on_support_change_default: true)
      create(:user_organization_membership, user: member_user, organization: org, status: "active")

      result_ids = org.notifiable_follower_set_for([:support_change]).map(&:first)
      expect(result_ids).to include(member_user.id)
    end

    it "excludes an active member with no follow row when global default is false" do
      member_user = create(:user, notify_on_support_change_default: false)
      create(:user_organization_membership, user: member_user, organization: org, status: "active")

      result_ids = org.notifiable_follower_set_for([:support_change]).map(&:first)
      expect(result_ids).not_to include(member_user.id)
    end

    it "returns tuples of [user_id, cadence] for follow-row followers" do
      follower = create(:user)
      create(:organization_follow, user: follower, organization: org,
        notification_cadence: :daily, notify_on_new_position: true)

      result = org.notifiable_follower_set_for([:new_position])
      tuple = result.find { |uid, _cadence| uid == follower.id }
      expect(tuple).not_to be_nil
      expect(tuple[1]).to eq("daily")
    end

    it "returns tuples of [user_id, cadence] for member-no-row followers using global cadence default" do
      member_user = create(:user, notify_on_new_position_default: true, org_position_cadence_default: :weekly)
      create(:user_organization_membership, user: member_user, organization: org, status: "active")

      result = org.notifiable_follower_set_for([:new_position])
      tuple = result.find { |uid, _cadence| uid == member_user.id }
      expect(tuple).not_to be_nil
      expect(tuple[1]).to eq("weekly")
    end

    it "includes a follower enabled for >=1 of the given change_types" do
      user = create(:user)
      create(:organization_follow, user: user, organization: org,
        notify_on_new_position: false, notify_on_support_change: true, notify_on_summary_change: false)

      # One switch left on (support changes) is enough, even with the others muted.
      result_ids = org.notifiable_follower_set_for([:new_position, :support_change]).map(&:first)
      expect(result_ids).to include(user.id)
    end

    it "excludes a follower muted for ALL of the given change_types" do
      muted_user = create(:user)
      create(:organization_follow, user: muted_user, organization: org,
        notify_on_new_position: false, notify_on_support_change: false, notify_on_summary_change: true)

      # This user muted new positions and support changes, and left only summary changes on.
      # We ask about new positions and support changes, so every type we asked about is
      # muted, and the user is left out.
      result_ids = org.notifiable_follower_set_for([:new_position, :support_change]).map(&:first)
      expect(result_ids).not_to include(muted_user.id)
    end

    # A change type nobody recognizes must notify no one. Both paths — people with a follow
    # row and members relying on defaults — have to agree and stay silent.
    it "excludes BOTH a follow-row follower and a member-no-row user for an unknown change_type" do
      follow_user = create(:user)
      create(:organization_follow, user: follow_user, organization: org,
        notify_on_new_position: true, notify_on_support_change: true, notify_on_summary_change: true)
      member_user = create(:user, notify_on_new_position_default: true)
      create(:user_organization_membership, user: member_user, organization: org, status: "active")

      result_ids = org.notifiable_follower_set_for([:totally_unknown_type]).map(&:first)
      expect(result_ids).not_to include(follow_user.id)
      expect(result_ids).not_to include(member_user.id)
    end

    it "does not produce N+1 queries for member-no-row lookups" do
      3.times do
        m = create(:user, notify_on_new_position_default: true)
        create(:user_organization_membership, user: m, organization: org, status: "active")
      end

      # Nobody has a follow row, so everyone goes through the member-defaults path.
      query_count = 0
      counter = ->(_name, _start, _finish, _id, payload) {
        query_count += 1 unless %w[SCHEMA TRANSACTION].include?(payload[:name])
      }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        org.notifiable_follower_set_for([:new_position])
      end

      # At most 3 queries: load members, load follow rows, load those users in one batch.
      expect(query_count).to be <= 3
    end
  end
end
