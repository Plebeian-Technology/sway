# == Schema Information
#
# Table name: user_organization_memberships
# Database name: primary
#
#  id              :integer          not null, primary key
#  role            :integer          not null
#  status          :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  organization_id :integer          not null
#  user_id         :integer          not null
#
# Indexes
#
#  idx_on_user_id_organization_id_7cc0c85071               (user_id,organization_id) UNIQUE
#  index_user_organization_memberships_on_organization_id  (organization_id)
#  index_user_organization_memberships_on_user_id          (user_id)
#
# Foreign Keys
#
#  organization_id  (organization_id => organizations.id)
#  user_id          (user_id => users.id)
#
require "rails_helper"

RSpec.describe UserOrganizationMembership, type: :model do
  describe "associations" do
    it "belongs to a user and an organization via factory" do
      record = create(:user_organization_membership)
      expect(record).to be_persisted
      expect(record.user).to be_a(User)
      expect(record.organization).to be_a(Organization)
    end
  end

  describe "role enum" do
    it "defaults to :standard" do
      record = create(:user_organization_membership)
      expect(record.role).to eq("standard")
      expect(record.admin?).to be(false)
    end

    it "supports the :admin trait" do
      record = create(:user_organization_membership, :admin)
      expect(record.role).to eq("admin")
      expect(record.admin?).to be(true)
    end
  end

  describe "#to_builder" do
    it "emits role as 'standard' for non-admin memberships" do
      record = create(:user_organization_membership)
      attrs = record.to_builder.attributes!
      expect(attrs["role"]).to eq("standard")
      expect(attrs["user_id"]).to eq(record.user.id)
    end

    it "emits role as 'admin' for admin memberships" do
      record = create(:user_organization_membership, :admin)
      attrs = record.to_builder.attributes!
      expect(attrs["role"]).to eq("admin")
    end
  end

  describe "initial state (state machine)" do
    it "lands in :pending when created without explicit status" do
      # Skip the factory, which sets status to "active", so the model's own starting state shows.
      user = create(:user)
      org = create(:organization)
      m = UserOrganizationMembership.create!(user: user, organization: org, role: :standard)
      expect(m.status).to eq("pending")
    end

    it "lands in :active when admin-seeded with explicit status: :active" do
      m = create(:user_organization_membership, role: :admin, status: :active)
      expect(m.status).to eq("active")
    end

    it "transitions :pending → :active via activate!" do
      user = create(:user)
      org = create(:organization)
      m = UserOrganizationMembership.create!(user: user, organization: org, role: :standard)
      expect { m.activate! }.to change { m.status }.from("pending").to("active")
    end

    it "raises InvalidTransition when activate! is called on already-active row" do
      m = create(:user_organization_membership, status: :active)
      expect { m.activate! }.to raise_error(StateMachines::InvalidTransition)
    end

    # Inviting a removed member back in.
    it "transitions :removed → :active via activate! (re-invite cycle)" do
      organization = create(:organization)
      _other_admin = create(:user_organization_membership, organization:, role: :admin, status: :active)
      m = create(:user_organization_membership, organization:, role: :standard, status: :active)
      m.remove!
      expect(m.reload.status).to eq("removed")
      expect { m.activate! }.to change { m.status }.from("removed").to("active")
    end
  end

  describe "remove event" do
    it "transitions :active → :removed via remove!" do
      organization = create(:organization)
      _other_admin = create(:user_organization_membership, organization:, role: :admin, status: :active)
      m = create(:user_organization_membership, organization:, role: :admin, status: :active)
      expect { m.remove! }.to change { m.status }.from("active").to("removed")
    end

    it "raises InvalidTransition when remove! called from :pending" do
      m = create(:user_organization_membership, status: :pending)
      expect { m.remove! }.to raise_error(StateMachines::InvalidTransition)
    end
  end

  describe "last-admin guard — paired validate/before_destroy" do
    let(:organization) { create(:organization) }

    context "with exactly one active admin" do
      let!(:only_admin) {
        create(:user_organization_membership, organization:, role: :admin, status: :active)
      }

      it "rejects destroy of the only admin (before_destroy :must_not_orphan_org_admin_on_destroy throws :abort)" do
        expect(only_admin.destroy).to be(false)
        expect(UserOrganizationMembership.where(id: only_admin.id)).to exist
      end

      it "rejects role demotion of the only admin (validator on: :update adds :base error)" do
        result = only_admin.update(role: :standard)
        expect(result).to be(false)
        expect(only_admin.errors[:base].join).to include("only admin")
      end

      it "rejects status: :removed update on the only admin (validator on: :update adds :base error)" do
        result = only_admin.update(status: :removed)
        expect(result).to be(false)
        expect(only_admin.errors[:base].join).to include("only admin")
      end

      it "rejects remove! of the only admin (raises StateMachines::InvalidTransition or ActiveRecord::RecordInvalid)" do
        expect { only_admin.remove! }.to raise_error(StandardError)
        only_admin.reload
        expect(only_admin.status).to eq("active")
      end
    end

    context "with two active admins (guard does not fire)" do
      let!(:admin_a) { create(:user_organization_membership, organization:, role: :admin, status: :active) }
      let!(:admin_b) { create(:user_organization_membership, organization:, role: :admin, status: :active) }

      it "permits destroy of one admin" do
        expect(admin_a.destroy).to be_truthy
      end

      it "permits role demotion of one admin" do
        expect(admin_a.update(role: :standard)).to be(true)
      end

      it "permits remove! of one admin" do
        expect { admin_a.remove! }.to change { admin_a.reload.status }.from("active").to("removed")
      end
    end

    context "before_destroy ordering — prepend: true halts dependent: :destroy cascade" do
      it "preserves the only-admin membership row when its parent User is destroyed via dependent: :destroy" do
        # @lat: [[user-organization-membership-admin-orphan-guard#The destroy-time guard]]
        admin_user = create(:user)
        only_admin = create(:user_organization_membership,
          user: admin_user, organization:, role: :admin, status: :active)

        # Delete through the User, so the cascade really runs.
        result = User.find(admin_user.id).destroy
        expect(result).to be(false)

        # The check fired before the cascade could delete the row.
        expect(UserOrganizationMembership.where(id: only_admin.id)).to exist
      end

      it "registers the before_destroy callback with prepend: true (sanity check via callback chain)" do
        callbacks = UserOrganizationMembership._destroy_callbacks.select { |cb|
          cb.kind == :before && cb.filter == :must_not_orphan_org_admin_on_destroy
        }
        expect(callbacks).not_to be_empty
        # prepend: true puts the callback at the front of the chain, so it runs first.
        first_before_destroy = UserOrganizationMembership._destroy_callbacks
          .find { |cb| cb.kind == :before }
        expect(first_before_destroy.filter).to eq(:must_not_orphan_org_admin_on_destroy)
      end
    end

    context "concurrent demotion race (with_lock semantics)" do
      let!(:admin_a) { create(:user_organization_membership, organization:, role: :admin, status: :active) }
      let!(:admin_b) { create(:user_organization_membership, organization:, role: :admin, status: :active) }

      it "serializes concurrent demotes via organization.with_lock (structural assertion)" do
        # @lat: [[user-organization-membership-admin-orphan-guard#__only_active_admin?: the shared check both guards call#Why the concurrent-demotion spec is a structural assertion, not a thread race]]
        org = admin_a.organization
        expect(org).to receive(:with_lock).at_least(:once).and_call_original
        admin_a.update(role: :standard)
      end
    end
  end
end
