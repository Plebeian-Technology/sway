# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Organizations::MembershipsController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:organization) { create(:organization) }

  describe "org-admin gate" do
    include_examples "requires organization admin",
      verb: :delete,
      path: -> {
        membership = create(:user_organization_membership,
          organization: organization, role: :standard, status: :active)
        "/organizations/#{organization.id}/memberships/#{membership.id}"
      }
  end

  # An unknown role in PATCH #update used to raise a KeyError and 500, from
  # UserOrganizationMembership.roles.fetch(params[:role]). The role is now
  # checked first, and a bad one gets a flash message and a redirect, like
  # every other write here.
  describe "PATCH /organizations/:organization_id/memberships/:id (role validation)" do
    it "rejects an unknown role with a flash alert instead of a KeyError 500" do
      _, user = setup
      # current_user is an admin of this organization, which is not a Sway admin.
      create(:user_organization_membership,
        user: user, organization: organization, role: :admin, status: :active)
      target = create(:user_organization_membership,
        organization: organization, role: :standard, status: :active)

      patch organization_membership_path(organization, target), params: {role: "superadmin"}

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to eq("Invalid role.")
      expect(target.reload.role).to eq("standard")
    end
  end

  describe "GET /organizations/:organization_id/memberships/:id" do
    it "renders the UserOrganizationMembership component" do
      _, user = setup
      membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )

      get organization_membership_path(organization, membership)

      expect(inertia).to render_component Pages::USER_ORGANIZATION_MEMBERSHIP
    end

    it "passes the membership prop" do
      _, user = setup
      membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )

      get organization_membership_path(organization, membership)

      expect(inertia).to have_props { |p| p.key?(:membership) }
    end

    it "includes organization data in the membership prop" do
      _, user = setup
      membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )

      get organization_membership_path(organization, membership)

      expect(inertia).to have_props { |p|
        membership_prop = p[:membership] || {}
        membership_prop.key?(:organization) ||
          membership_prop.key?("organization")
      }
    end

    it "sends each position's source kind so the page can say who wrote it" do
      _, user = setup
      membership = create(:user_organization_membership, user: user, organization: organization)
      create(:organization_bill_position,
        organization: organization,
        source_kind: OrganizationBillPosition::SourceKind::ORGANIZATION)

      get organization_membership_path(organization, membership)

      expect(inertia).to have_props { |p|
        p[:membership][:positions].pluck(:source_kind) ==
          [OrganizationBillPosition::SourceKind::ORGANIZATION]
      }
    end

    it "sends each position's source URL so the page can link to its source" do
      _, user = setup
      membership = create(:user_organization_membership, user: user, organization: organization)
      create(:organization_bill_position,
        organization: organization,
        source_kind: OrganizationBillPosition::SourceKind::NEWS_ARTICLE,
        source_url: "https://news.example.com/story")

      get organization_membership_path(organization, membership)

      expect(inertia).to have_props { |p|
        p[:membership][:positions].pluck(:source_url) == ["https://news.example.com/story"]
      }
    end

    it "permits a pending member to view their own membership without member PII or pending changes" do
      _, user = setup
      other_admin = create(:user, full_name: "Secret Admin", email: "secret-admin@example.com")
      create(:user_organization_membership, user: other_admin, organization: organization, role: :admin, status: :active)
      pending_membership = create(
        :user_organization_membership,
        user: user,
        organization: organization,
        role: :standard,
        status: :pending
      )

      get organization_membership_path(organization, pending_membership),
        headers: {"Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      membership_json = response.parsed_body.fetch("membership")
      expect(membership_json["id"]).to eq(pending_membership.id)
      expect(Array(membership_json["members"])).to be_empty
      expect(Array(membership_json["pending_changes"])).to be_empty
    end

    it "rejects a removed member requesting their membership detail page (HTML and JSON)" do
      _, user = setup
      other_admin = create(:user, full_name: "Active Admin", email: "active-admin@example.com")
      create(:user_organization_membership, user: other_admin, organization: organization, role: :admin, status: :active)
      removed_membership = create(
        :user_organization_membership,
        user: user,
        organization: organization,
        role: :admin,
        status: :active
      )
      removed_membership.remove!

      get organization_membership_path(organization, removed_membership)
      expect(response).to redirect_to("/organizations/#{organization.id}")
      expect(flash[:alert]).to eq("Forbidden")

      get organization_membership_path(organization, removed_membership),
        headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include("active-admin@example.com")
    end

    it "rejects a non-member requesting a membership detail page without raising 500" do
      _, _user = setup
      other_membership = create(:user_organization_membership, organization: organization, status: :active)

      get organization_membership_path(organization, other_membership)
      expect(response).to redirect_to("/organizations/#{organization.id}")

      get organization_membership_path(organization, other_membership),
        headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:forbidden)
    end

    it "rejects a member requesting another member's membership ID on #show" do
      _, user = setup
      create(:user_organization_membership, user: user, organization: organization, role: :admin, status: :active)
      other_membership = create(:user_organization_membership, organization: organization, role: :standard, status: :active)

      get organization_membership_path(organization, other_membership),
        headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "DELETE /organizations/:organization_id/memberships/leave (A5.2 self-leave)" do
    it "transitions the current user's active membership to :removed and surfaces the flash via Inertia shared data" do
      _, user = setup
      membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization,
          role: :standard,
          status: :active
        )

      delete leave_organization_memberships_path(organization)

      membership.reload
      expect(membership.status).to eq("removed")
      expect(response).to redirect_to(users_organization_memberships_path)

      follow_redirect!

      expect(inertia).to render_component Pages::USER_ORGANIZATION_MEMBERSHIPS
      expect(inertia).to have_props { |p|
        flash_h = p[:flash] || {}
        flash_h[:notice].to_s.include?("You have left") ||
          flash_h["notice"].to_s.include?("You have left")
      }
      # The just-left org no longer appears in the active memberships list.
      expect(inertia).to have_props { |p|
        memberships = p[:memberships] || []
        memberships.none? { |m| (m[:organization] || m["organization"])[:id] == organization.id }
      }
    end

    it "blocks self-leave for the only active admin and surfaces the guard message via Inertia flash" do
      _, user = setup
      membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization,
          role: :admin,
          status: :active
        )

      delete leave_organization_memberships_path(organization)

      membership.reload
      expect(membership.status).to eq("active")

      follow_redirect!

      expect(inertia).to render_component Pages::USER_ORGANIZATION_MEMBERSHIPS
      expect(inertia).to have_props { |p|
        flash_h = p[:flash] || {}
        message = flash_h[:alert].to_s.presence || flash_h["alert"].to_s
        message.include?("only admin")
      }
    end

    it "permits an admin to leave when a second active admin exists" do
      _, user = setup
      admin_a =
        create(
          :user_organization_membership,
          user: user,
          organization: organization,
          role: :admin,
          status: :active
        )
      _admin_b =
        create(
          :user_organization_membership,
          user: create(:user),
          organization: organization,
          role: :admin,
          status: :active
        )

      delete leave_organization_memberships_path(organization)

      admin_a.reload
      expect(admin_a.status).to eq("removed")

      follow_redirect!

      expect(inertia).to render_component Pages::USER_ORGANIZATION_MEMBERSHIPS
      expect(inertia).to have_props { |p|
        flash_h = p[:flash] || {}
        flash_h[:notice].to_s.include?("You have left") ||
          flash_h["notice"].to_s.include?("You have left")
      }
    end

    it "rejects self-leave when the user has no membership in the org and lands an Inertia error flash" do
      _, _user = setup

      delete leave_organization_memberships_path(organization)

      expect(response).to redirect_to(users_organization_memberships_path)

      follow_redirect!

      expect(inertia).to render_component Pages::USER_ORGANIZATION_MEMBERSHIPS
      expect(inertia).to have_props { |p|
        flash_h = p[:flash] || {}
        message = flash_h[:alert].to_s.presence || flash_h["alert"].to_s
        message.include?("not an active member")
      }
    end

    it "treats a removed membership as not-a-member" do
      _, user = setup
      membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization,
          role: :standard,
          status: :active
        )
      membership.remove!

      delete leave_organization_memberships_path(organization)

      follow_redirect!

      expect(inertia).to render_component Pages::USER_ORGANIZATION_MEMBERSHIPS
      expect(inertia).to have_props { |p|
        flash_h = p[:flash] || {}
        message = flash_h[:alert].to_s.presence || flash_h["alert"].to_s
        message.include?("not an active member")
      }
    end
  end
end
