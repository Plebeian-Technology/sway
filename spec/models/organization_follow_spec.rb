# frozen_string_literal: true

# == Schema Information
#
# Table name: organization_follows
# Database name: primary
#
#  id                       :integer          not null, primary key
#  notification_cadence     :integer          default("every_change"), not null
#  notify_on_new_position   :boolean          default(TRUE), not null
#  notify_on_summary_change :boolean          default(TRUE), not null
#  notify_on_support_change :boolean          default(TRUE), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  organization_id          :integer          not null
#  user_id                  :integer          not null
#
# Indexes
#
#  idx_organization_follows_on_user_and_organization  (user_id,organization_id) UNIQUE
#  index_organization_follows_on_organization_id      (organization_id)
#
# Foreign Keys
#
#  organization_id  (organization_id => organizations.id)
#  user_id          (user_id => users.id)
#
require "rails_helper"

RSpec.describe OrganizationFollow, type: :model do
  describe "associations" do
    it "belongs to a user and an organization" do
      follow = create(:organization_follow)
      expect(follow.user).to be_a(User)
      expect(follow.organization).to be_a(Organization)
    end
  end

  describe "uniqueness" do
    it "prevents the same user from following the same organization twice" do
      follow = create(:organization_follow)
      duplicate = build(:organization_follow, user: follow.user, organization: follow.organization)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:user_id]).to include("has already been taken")
    end

    it "allows the same user to follow different organizations" do
      user = create(:user, is_registration_complete: true)
      org_a = create(:organization)
      org_b = create(:organization, name: "Other Org")
      create(:organization_follow, user: user, organization: org_a)
      duplicate_user_diff_org = build(:organization_follow, user: user, organization: org_b)
      expect(duplicate_user_diff_org).to be_valid
    end

    it "raises on a database-level duplicate insertion attempt" do
      follow = create(:organization_follow)
      expect {
        OrganizationFollow.new(user: follow.user, organization: follow.organization).save(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "defaults" do
    it "has notification_cadence every_change by default" do
      follow = OrganizationFollow.new
      expect(follow.notification_cadence).to eq("every_change")
    end

    it "has all event-type booleans true by default" do
      follow = OrganizationFollow.new
      expect(follow.notify_on_new_position).to be(true)
      expect(follow.notify_on_support_change).to be(true)
      expect(follow.notify_on_summary_change).to be(true)
    end

    it "persists defaults to the database" do
      follow = create(:organization_follow)
      follow.reload
      expect(follow.notification_cadence).to eq("every_change")
      expect(follow.notify_on_new_position).to be(true)
      expect(follow.notify_on_support_change).to be(true)
      expect(follow.notify_on_summary_change).to be(true)
    end
  end

  describe "#muted_for?" do
    subject(:follow) { build(:organization_follow) }

    it "returns false when notify_on_new_position is true" do
      follow.notify_on_new_position = true
      expect(follow.muted_for?(:new_position)).to be(false)
    end

    it "returns true when notify_on_new_position is false" do
      follow.notify_on_new_position = false
      expect(follow.muted_for?(:new_position)).to be(true)
    end

    it "returns false when notify_on_support_change is true" do
      follow.notify_on_support_change = true
      expect(follow.muted_for?(:support_change)).to be(false)
    end

    it "returns true when notify_on_support_change is false" do
      follow.notify_on_support_change = false
      expect(follow.muted_for?(:support_change)).to be(true)
    end

    it "returns false when notify_on_summary_change is true" do
      follow.notify_on_summary_change = true
      expect(follow.muted_for?(:summary_change)).to be(false)
    end

    it "returns true when notify_on_summary_change is false" do
      follow.notify_on_summary_change = false
      expect(follow.muted_for?(:summary_change)).to be(true)
    end

    # An unrecognized change_type must notify no one — fail closed, not open.
    # This matches Organization#notifiable_follower_set_for's own
    # member-no-row branch, which also excludes unknown types.
    it "returns true (muted, fail-closed) for an unknown change_type" do
      expect(follow.muted_for?(:unknown_type)).to be(true)
    end
  end

  describe ".seed_attrs_from" do
    it "returns a hash seeded from the user's global defaults" do
      user = build(:user,
        org_position_cadence_default: :daily,
        notify_on_new_position_default: false,
        notify_on_support_change_default: true,
        notify_on_summary_change_default: false)

      attrs = OrganizationFollow.seed_attrs_from(user)

      # notification_cadence comes from user.org_position_cadence_default (enum string key)
      expect(attrs[:notification_cadence]).to eq("daily")
      expect(attrs[:notify_on_new_position]).to be(false)
      expect(attrs[:notify_on_support_change]).to be(true)
      expect(attrs[:notify_on_summary_change]).to be(false)
    end

    it "returns all-on defaults when the user has factory-default columns" do
      user = build(:user)
      attrs = OrganizationFollow.seed_attrs_from(user)

      # Default cadence = every_change (enum string key)
      expect(attrs[:notification_cadence]).to eq("every_change")
      expect(attrs[:notify_on_new_position]).to be(true)
      expect(attrs[:notify_on_support_change]).to be(true)
      expect(attrs[:notify_on_summary_change]).to be(true)
    end

    it "produces attrs that can be assigned to a new follow" do
      user = build(:user, org_position_cadence_default: :weekly)
      attrs = OrganizationFollow.seed_attrs_from(user)

      follow = OrganizationFollow.new(attrs)
      expect(follow.notification_cadence).to eq("weekly")
    end
  end

  describe "User#cascade_org_pref_off! (REQ-6)" do
    let(:user) { create(:user) }
    let(:org_a) { create(:organization) }
    let(:org_b) { create(:organization, name: "Org B") }
    let(:org_c) { create(:organization, name: "Org C") }

    before do
      create(:organization_follow, user: user, organization: org_a)
      create(:organization_follow, user: user, organization: org_b)
      create(:organization_follow, user: user, organization: org_c)
    end

    it "sets notify_on_summary_change to false on all of the user's follows" do
      user.cascade_org_pref_off!(:notify_on_summary_change)

      user.organization_follows.reload.each do |follow|
        expect(follow.notify_on_summary_change).to be(false)
      end
    end

    it "stamps updated_at on all affected rows (update_all, not update_columns)" do
      # Force the follow rows to a known-old timestamp so the assertion proves
      # updated_at STRICTLY advanced (a no-op stamp would fail), with no flaky
      # sub-second equality.
      old_timestamp = 1.hour.ago
      user.organization_follows.update_all(updated_at: old_timestamp)

      user.cascade_org_pref_off!(:notify_on_new_position)

      user.organization_follows.reload.each do |follow|
        expect(follow.updated_at).to be > old_timestamp
      end
    end

    it "accepts a String column name (IN-03 — params-derived input cascades, no raise)" do
      user.cascade_org_pref_off!("notify_on_summary_change")

      user.organization_follows.reload.each do |follow|
        expect(follow.notify_on_summary_change).to be(false)
      end
    end

    it "raises ArgumentError for an unknown column" do
      expect { user.cascade_org_pref_off!(:arbitrary_column) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for an unknown String column (allowlist still enforced)" do
      expect { user.cascade_org_pref_off!("arbitrary_column") }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError for a non-cascadable column" do
      expect { user.cascade_org_pref_off!(:notification_cadence) }.to raise_error(ArgumentError)
    end
  end
end
