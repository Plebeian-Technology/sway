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

  # An org's followers are its active members plus anyone who explicitly followed it,
  # counted once each even if they are both.
  describe "#follower_set and #follower_count" do
    let(:org) { create(:organization) }

    it "returns empty array and 0 for an org with no members or follows" do
      expect(org.follower_set).to eq([])
      expect(org.follower_count).to eq(0)
    end

    it "includes active members in the follower set" do
      member_user = create(:user)
      create(:user_organization_membership, user: member_user, organization: org, status: "active")

      expect(org.follower_set).to include(member_user.id)
      expect(org.follower_count).to eq(1)
    end

    it "includes explicit non-member follows in the follower set" do
      follower_user = create(:user)
      create(:organization_follow, user: follower_user, organization: org)

      expect(org.follower_set).to include(follower_user.id)
      expect(org.follower_count).to eq(1)
    end

    it "dedupes a user who is both an active member and an explicit follower" do
      dual_user = create(:user)
      create(:user_organization_membership, user: dual_user, organization: org, status: "active")
      create(:organization_follow, user: dual_user, organization: org)

      expect(org.follower_set.count(dual_user.id)).to eq(1)
      expect(org.follower_count).to eq(1)
    end

    it "returns M + F (deduplicated) when M active members and F non-member follows" do
      member1 = create(:user)
      member2 = create(:user)
      follower1 = create(:user)
      create(:user_organization_membership, user: member1, organization: org, status: "active")
      create(:user_organization_membership, user: member2, organization: org, status: "active")
      create(:organization_follow, user: follower1, organization: org)

      expect(org.follower_count).to eq(3)
      expect(org.follower_set).to contain_exactly(member1.id, member2.id, follower1.id)
    end

    it "excludes pending members from the follower set" do
      pending_user = create(:user)
      create(:user_organization_membership, user: pending_user, organization: org, status: "pending")

      expect(org.follower_set).not_to include(pending_user.id)
    end

    it "excludes removed members from the follower set" do
      removed_user = create(:user)
      create(:user_organization_membership, user: removed_user, organization: org, status: "removed")

      expect(org.follower_set).not_to include(removed_user.id)
    end

    it "includes muted explicit followers in follower_count (muted != unfollowed)" do
      muted_follower = create(:user)
      create(:organization_follow, :muted, user: muted_follower, organization: org)

      # Muting only silences notifications. The person still follows the org, so they count.
      expect(org.follower_set).to include(muted_follower.id)
      expect(org.follower_count).to eq(1)
    end
  end

  # follower_count is one of the org's public fields, so to_public_json hands it out.
  describe "#to_public_json" do
    let(:org) { create(:organization) }

    it "includes follower_count as an Integer" do
      result = org.to_public_json
      expect(result).to have_key(:follower_count)
      expect(result[:follower_count]).to be_a(Integer)
    end

    it "follower_count in to_public_json reflects the deduped set" do
      active_user = create(:user)
      create(:user_organization_membership, user: active_user, organization: org, status: "active")
      create(:organization_follow, user: active_user, organization: org)

      # One person who is both a member and a follower still counts as 1.
      expect(org.to_public_json[:follower_count]).to eq(1)
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

  # Counts followers for a whole list of orgs in one query, still counting each person once.
  describe ".follower_counts_for" do
    it "returns deduped counts keyed by org id" do
      org1 = create(:organization, name: "Counts 1")
      org2 = create(:organization, name: "Counts 2")
      u1 = create(:user)
      u2 = create(:user)
      create(:organization_follow, user: u1, organization: org1)
      create(:user_organization_membership, user: u2, organization: org1, status: "active")
      create(:organization_follow, user: u1, organization: org2)

      counts = Organization.follower_counts_for([org1.id, org2.id])
      expect(counts[org1.id]).to eq(2)
      expect(counts[org2.id]).to eq(1)
    end

    it "counts a user who is BOTH member and follower exactly once (matches #follower_count)" do
      org = create(:organization, name: "Dedup org")
      u = create(:user)
      create(:organization_follow, user: u, organization: org)
      create(:user_organization_membership, user: u, organization: org, status: "active")

      expect(Organization.follower_counts_for([org.id])[org.id]).to eq(1)
      expect(org.follower_count).to eq(1)
    end

    it "returns an empty hash for an empty id set" do
      expect(Organization.follower_counts_for([])).to eq({})
    end

    it "issues a single grouped query for many orgs (no N+1)" do
      orgs = Array.new(3) { |i| create(:organization, name: "NQ #{i}") }
      orgs.each { |o| create(:organization_follow, organization: o) }

      query_count = 0
      counter = ->(*, **) { query_count += 1 }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") do
        Organization.follower_counts_for(orgs.map(&:id))
      end

      # One combined, grouped query covering every org — not one query per org.
      expect(query_count).to be <= 2
    end
  end
end
