require "rails_helper"

RSpec.describe "UserOrganizationMemberships", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:organization) { create(:organization) }

  # ── JSON for mobile callers, alongside the web pages ───────────────────────
  describe "GET /users/organization_memberships (JSON / mobile bearer)" do
    it "returns memberships array for bearer JSON request" do
      _, user = setup
      membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )
      raw_token = "test-bearer-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user, token: raw_token)

      get users_organization_memberships_path,
        headers: {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
      body = response.parsed_body
      expect(body["memberships"]).to be_an(Array)
      expect(body["memberships"].pluck("id")).to include(membership.id)
      expect(body).to have_key("pending_memberships")
    end
  end

  describe "GET /organizations/:org_id/memberships/:id (JSON / mobile bearer)" do
    it "returns membership payload for bearer JSON request" do
      _, user = setup
      membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )
      raw_token = "test-bearer-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user, token: raw_token)

      get organization_membership_path(organization, membership),
        headers: {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
      body = response.parsed_body
      expect(body["membership"]).to be_a(Hash)
      expect(body.dig("membership", "id")).to eq(membership.id)
    end
  end
  # ───────────────────────────────────────────────────────────────────────────

  describe "GET user_organization_memberships" do
    it "renders the memberships index" do
      _, user = setup
      membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )

      get users_organization_memberships_path
      expect(response).to have_http_status(:ok)
      # Pin the component and the props the index page gets.
      expect(inertia).to render_component(Pages::USER_ORGANIZATION_MEMBERSHIPS)
      expect(inertia.props.keys).to include("tab", "user", "memberships", "pending_memberships")
      expect(
        inertia.props.deep_symbolize_keys[:user][:memberships].pluck(:id)
      ).to include(membership.id)
    end

    it "keeps the tab response prop while reading the canonical query name" do
      setup

      get users_organization_memberships_path, params: {org_tab: "changes"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab]).to eq("changes")
    end

    it "defaults an explicitly empty canonical org_tab instead of reading conflicting aliases" do
      setup

      get users_organization_memberships_path,
        params: {org_tab: "", tab: "changes", tab_key: "members"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab]).to eq("positions")
    end

    it "keeps the tab response prop while reading the legacy query name" do
      setup

      get users_organization_memberships_path, params: {tab: "changes"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab]).to eq("changes")
    end

    it "keeps the tab response prop while reading the legacy tab_key name" do
      setup

      get users_organization_memberships_path, params: {tab_key: "changes"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab]).to eq("changes")
    end

    it "reads the memberships and their organizations once for both lists" do
      _, user = setup
      create(:user_organization_membership, user: user, organization: organization, status: :active)
      create(:user_organization_membership, user: user, organization: create(:organization), status: :active)
      create(:user_organization_membership, user: user, organization: create(:organization), status: :pending)

      statements = []
      subscriber =
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          statements << payload[:sql].to_s
        end
      begin
        get users_organization_memberships_path
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end

      expect(response).to have_http_status(:ok)
      expect(statements.grep(/FROM "user_organization_memberships"/).size).to eq(1)
      expect(statements.grep(/FROM "organizations"/).size).to eq(1)
    end

    it "keeps pending memberships out of the active list and in their own" do
      _, user = setup
      org2 = create(:organization)
      pending_mem = create(
        :user_organization_membership,
        user: user,
        organization: org2,
        status: :pending
      )
      active_mem = create(
        :user_organization_membership,
        user: user,
        organization: organization,
        status: :active
      )

      get users_organization_memberships_path

      expect(response).to have_http_status(:ok)
      props = inertia.props.deep_symbolize_keys
      pending_ids = props[:pending_memberships]&.pluck(:id) || []
      expect(pending_ids).to include(pending_mem.id)
      expect(pending_ids).not_to include(active_mem.id)
    end

    it "excludes pending memberships from the active memberships list" do
      _, user = setup
      org2 = create(:organization)
      pending_mem = create(
        :user_organization_membership,
        user: user,
        organization: org2,
        status: :pending
      )
      active_mem = create(
        :user_organization_membership,
        user: user,
        organization: organization,
        status: :active
      )

      get users_organization_memberships_path

      props = inertia.props.deep_symbolize_keys
      membership_ids = props[:memberships]&.pluck(:id) || []
      expect(membership_ids).to include(active_mem.id)
      pending_in_active = props[:memberships]&.any? { |m| m[:id] == pending_mem.id } || false
      expect(pending_in_active).to be false
    end
  end

  describe "GET user_organization_memberships/:id" do
    it "shows the membership details" do
      _, user = setup
      membership =
        create(
          :user_organization_membership,
          user: user,
          organization: organization
        )

      get organization_membership_path(organization, membership)
      expect(response).to have_http_status(:ok)
      expect(inertia.props.deep_symbolize_keys.dig(:membership, :id)).to eql(
        membership.id
      )
    end

    it "defaults to the positions tab when no tab parameter is present" do
      _, user = setup
      membership = create(:user_organization_membership, user:, organization:)

      get organization_membership_path(organization, membership)

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab]).to eq("positions")
    end

    it "uses the canonical org_tab value and gives it precedence over aliases" do
      _, user = setup
      membership = create(:user_organization_membership, user:, organization:)

      get organization_membership_path(organization, membership),
        params: {org_tab: "positions", tab: "changes", tab_key: "members"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab]).to eq("positions")
    end

    it "defaults an explicitly empty canonical org_tab without falling back to aliases" do
      _, user = setup
      membership = create(:user_organization_membership, user:, organization:)

      get organization_membership_path(organization, membership),
        params: {org_tab: "", tab: "changes", tab_key: "members"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab]).to eq("positions")
    end

    it "reads the legacy tab query name" do
      _, user = setup
      membership = create(:user_organization_membership, user:, organization:)

      get organization_membership_path(organization, membership), params: {tab: "changes"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab]).to eq("changes")
    end

    it "reads the legacy tab_key query name" do
      _, user = setup
      membership = create(:user_organization_membership, user:, organization:)

      get organization_membership_path(organization, membership), params: {tab_key: "approvals"}

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:tab]).to eq("approvals")
    end
  end

  describe "PATCH user_organization_memberships/:id" do
    context "as an admin" do
      it "updates the member's role" do
        _, admin = setup
        admin_membership =
          create(
            :user_organization_membership,
            user: admin,
            organization: organization,
            role: "admin"
          )
        member = create(:user)
        member_membership =
          create(
            :user_organization_membership,
            user: member,
            organization: organization,
            role: :standard
          )

        patch organization_membership_path(organization, member_membership),
          params: {
            role: "admin"
          }

        expect(response).to redirect_to(
          organization_membership_path(organization, admin_membership)
        )
        expect(member_membership.reload.role).to eq("admin")
      end
    end

    context "as a non-admin" do
      it "does not allow updating the member's role" do
        _, user = setup
        membership =
          create(
            :user_organization_membership,
            user: user,
            organization: organization,
            role: :standard
          )
        other = create(:user)
        other_membership =
          create(
            :user_organization_membership,
            user: other,
            organization: organization,
            role: :standard
          )

        patch organization_membership_path(organization, membership),
          params: {
            working_membership_id: other_membership.id,
            role: "admin"
          }

        expect(response).to redirect_to(
          organization_membership_path(organization, membership)
        )
        expect(flash[:alert]).to eq("Forbidden")
        expect(other_membership.reload.role).to eq("standard")
      end
    end
  end

  describe "DELETE user_organization_memberships/:id" do
    context "as an admin" do
      it "removes the membership" do
        _, admin = setup
        admin_membership =
          create(
            :user_organization_membership,
            user: admin,
            organization: organization,
            role: "admin"
          )
        member = create(:user)
        member_membership =
          create(
            :user_organization_membership,
            user: member,
            organization: organization,
            role: :standard
          )

        expect do
          delete organization_membership_path(organization, member_membership)
        end.to change(UserOrganizationMembership, :count).by(-1)

        expect(response).to redirect_to(
          organization_membership_path(organization, admin_membership)
        )
        expect(flash[:notice]).to eq("Member removed.")
      end
    end

    context "as a non-admin" do
      it "does not allow removing the membership" do
        _, user = setup
        membership =
          create(
            :user_organization_membership,
            user: user,
            organization: organization,
            role: :standard
          )
        other = create(:user)
        other_membership =
          create(
            :user_organization_membership,
            user: other,
            organization: organization,
            role: :standard
          )

        expect do
          delete organization_membership_path(organization, other_membership)
        end.not_to change(UserOrganizationMembership, :count)

        expect(response).to redirect_to(
          organization_membership_path(organization, membership)
        )
        expect(flash[:alert]).to eq("Forbidden")
      end
    end

    context "when removing own membership" do
      it "redirects to memberships index" do
        _, user = setup
        # Make this membership an admin AND add a second admin, so the
        # last-admin rule does NOT block removal. That rule only fires when
        # removing would leave the org with no active admins.
        membership =
          create(
            :user_organization_membership,
            user: user,
            organization: organization,
            role: "admin"
          )
        # Second admin prevents last-admin guard from blocking self-removal.
        second_admin = create(:user).tap { |u| complete_registration_with_active_link(u) }
        create(:user_organization_membership, user: second_admin, organization: organization, role: "admin")

        expect do
          delete organization_membership_path(organization, membership)
        end.to change(UserOrganizationMembership, :count).by(-1)

        expect(response).to redirect_to(users_organization_memberships_path)
      end
    end
  end
end
