# frozen_string_literal: true

require "rails_helper"

# @lat: [[pending-org-digest-entry-design#Why PendingOrganizationDigestEntry is a durable queue]]
# == Schema Information
#
# Table name: pending_organization_digest_entries
# Database name: primary
#
#  id           :integer          not null, primary key
#  cadence      :string           not null
#  change_types :string           not null
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  bill_id      :integer          not null
#  org_id       :integer          not null
#  user_id      :integer          not null
#
# Indexes
#
#  idx_pending_org_digest_on_cadence_created_at          (cadence,created_at)
#  index_pending_organization_digest_entries_on_user_id  (user_id)
#
RSpec.describe PendingOrganizationDigestEntry, type: :model do
  include_context "Setup"

  # @lat: [[rbs-signatures#Why global spec helper names have unique signatures]]
  def build_pending_entry(user, **overrides)
    described_class.new(
      {
        user: user,
        cadence: "daily",
        org_id: 1,
        bill_id: 1,
        change_types: "new_position"
      }.merge(overrides)
    )
  end

  # Checks the model adds on top of the database's NOT NULL columns: a value must be
  # there, and it must be one of the allowed choices.
  describe "validations (IN-01)" do
    it "is valid for daily and weekly cadences" do
      _sway_locale, user = setup
      %w[daily weekly].each do |cadence|
        expect(build_pending_entry(user, cadence: cadence)).to be_valid
      end
    end

    it "rejects a cadence outside daily/weekly (silently-dropped digest guard)" do
      _sway_locale, user = setup
      %w[every_change monthly bogus].each do |cadence|
        entry = build_pending_entry(user, cadence: cadence)
        expect(entry.valid?).to be(false)
        expect(entry.errors[:cadence]).to be_present
      end
    end

    it "requires change_types, org_id, and bill_id" do
      _sway_locale, user = setup
      %i[change_types org_id bill_id].each do |attr|
        entry = build_pending_entry(user, attr => nil)
        expect(entry.valid?).to be(false)
        expect(entry.errors[attr]).to be_present
      end
    end
  end

  # This table has no database foreign key pointing at users, so the database will not
  # clear out a deleted user's rows for us. Rails has to do it: User declares
  # has_many :pending_org_digest_entries, dependent: :destroy. Without that, rows for
  # deleted users would sit here forever.
  describe "User#destroy cascade (WR-01)" do
    it "destroys the user's pending digest entries on User#destroy" do
      _sway_locale, user = setup
      build_pending_entry(user).save!
      build_pending_entry(user, cadence: "weekly").save!

      expect { user.destroy }
        .to change { described_class.where(user_id: user.id).count }.from(2).to(0)
    end
  end
end
