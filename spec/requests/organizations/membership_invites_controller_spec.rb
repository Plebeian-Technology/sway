# frozen_string_literal: true

require "rails_helper"

RSpec.describe Organizations::MembershipInvitesController, type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:organization) { create(:organization) }
  let(:admin_user) do
    create(:user).tap { |u| complete_registration_with_active_link(u) }
  end
  let!(:admin_membership) {
    create(:user_organization_membership, user: admin_user, organization: organization, role: :admin, status: :active)
  }
  let(:invitee_email) { "invitee@example.com" }
  let(:invitee_user) do
    create(:user, email: invitee_email).tap do |u|
      complete_registration_with_active_link(u)
    end
  end

  def sign_in(user)
    session_hash[:user_id] = user.id
  end

  def signed_token(invite)
    invite.signed_id(purpose: :accept_invite, expires_at: invite.expires_at)
  end

  describe "GET #confirm_accept (signed-token landing)" do
    let!(:invite) {
      create(:user_organization_membership_invite,
        organization: organization, invitee_email: invitee_email, inviter: admin_user)
    }

    context "when current_user matches invitee_email" do
      it "(a part 1) renders the Inertia confirm page with 200" do
        sign_in(invitee_user)
        get "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/confirm_accept"
        expect(response.status).to eq(200)
        # Pin down which component renders and which props it receives: the
        # front end reads signed_token, organization, inviter_name and
        # expires_at.
        expect(inertia).to render_component(Pages::ORGANIZATION_INVITE_CONFIRM)
        expect(inertia.props.keys).to include(
          "signed_token",
          "organization",
          "inviter_name",
          "expires_at"
        )
      end
    end

    # @lat: [[membership-invite-accept-flow#MembershipInviteConfirm.tsx, the frontend confirm page]]
    context "when the mobile app asks with a bearer token" do
      let(:confirm_path) { "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/confirm_accept" }

      def bearer_headers_for(bearer)
        raw_token = "test-bearer-#{SecureRandom.hex(8)}"
        ApiKey.create!(bearer:, token: raw_token)
        {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}
      end

      it "returns the confirm props as JSON for a valid pending invite" do
        get confirm_path, headers: bearer_headers_for(invitee_user)

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body.keys).to match_array(%w[signed_token organization inviter_name expires_at])
        expect(body["signed_token"]).to eq(signed_token(invite))
        expect(body["organization"].keys).to match_array(%w[id sway_locale_id name icon_url])
        expect(body["organization"]).to include("id" => organization.id, "name" => organization.name)
        expect(body["inviter_name"]).to eq(admin_user.full_name)
        expect(body["expires_at"]).to be_a(String)
      end

      it "returns 403 with errors when the user's email does not match" do
        other_user = create(:user, email: "other@example.com").tap { |u| complete_registration_with_active_link(u) }

        get confirm_path, headers: bearer_headers_for(other_user)

        expect(response).to have_http_status(:forbidden)
        expect(response.parsed_body).to eq({"errors" => ["Forbidden"]})
      end

      it "returns 410 with errors when the invite is expired" do
        invite.update_columns(expires_at: 1.day.ago)

        get confirm_path, headers: bearer_headers_for(invitee_user)

        expect(response).to have_http_status(:gone)
        expect(response.parsed_body).to eq({"errors" => ["Invitation expired."]})
      end

      it "returns 404 with errors when the token is for a different organization" do
        other_org = create(:organization)

        get "/organizations/#{other_org.id}/membership_invites/#{signed_token(invite)}/confirm_accept",
          headers: bearer_headers_for(invitee_user)

        expect(response).to have_http_status(:not_found)
        expect(response.parsed_body).to eq({"errors" => ["Invitation not found."]})
      end
    end

    context "(b) when current_user does NOT match invitee_email" do
      let(:other_user) do
        create(:user, email: "other@example.com").tap do |u|
          complete_registration_with_active_link(u)
        end
      end

      it "returns 403 for JSON, 303 redirect with flash for HTML" do
        sign_in(other_user)
        get "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/confirm_accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(403)

        sign_in(other_user)
        get "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/confirm_accept"
        expect(response.status).to eq(303)
        expect(flash[:alert]).to eq("Forbidden")
      end
    end

    context "(d) when invite is expired" do
      it "returns 410 for JSON callers (verifier and column layer surface the same status)" do
        # Two things can reject an expired invite: find_signed! raising
        # InvalidSignature, and the expiry check on the column. Both now end up
        # in the same :gone branch, so JSON callers always see one status.
        invite.update_columns(expires_at: 1.day.ago)
        token = invite.signed_id(purpose: :accept_invite, expires_at: 1.day.ago)
        sign_in(invitee_user)
        get "/organizations/#{organization.id}/membership_invites/#{token}/confirm_accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(410)
      end

      it "(WR-10) returns 303 redirect with 'Invitation expired.' flash for HTML callers" do
        invite.update_columns(expires_at: 1.day.ago)
        token = invite.signed_id(purpose: :accept_invite, expires_at: 1.day.ago)
        sign_in(invitee_user)
        get "/organizations/#{organization.id}/membership_invites/#{token}/confirm_accept"
        expect(response.status).to eq(303)
        expect(flash[:alert]).to eq("Invitation expired.")
      end
    end

    context "(f) when token is signature-tampered" do
      it "returns 410 for JSON (verifier-layer rejection routed through :gone, WR-10)" do
        # A tampered signature and an expired one both raise
        # ActiveSupport::MessageVerifier::InvalidSignature, and the rescue
        # cannot tell them apart. Both come back as :gone with "Invitation
        # expired." That message fits either way — the invite is unusable.
        token = signed_token(invite)
        tampered = token[0..-3] + "ZZ"
        sign_in(invitee_user)
        get "/organizations/#{organization.id}/membership_invites/#{tampered}/confirm_accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(410)
      end
    end

    context "(e) when invite is revoked" do
      it "returns 422 for JSON, 303 redirect with flash for HTML" do
        invite.update!(revoked_at: Time.current)
        sign_in(invitee_user)
        get "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/confirm_accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(422)

        sign_in(invitee_user)
        get "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/confirm_accept"
        expect(response.status).to eq(303)
        expect(flash[:alert]).to eq("This invitation is no longer valid.")
      end
    end

    context "(g WR-01) cross-organization URL/invite mismatch" do
      it "returns 404 for JSON when params[:organization_id] differs from invite.organization_id" do
        other_org = create(:organization)
        sign_in(invitee_user)
        get "/organizations/#{other_org.id}/membership_invites/#{signed_token(invite)}/confirm_accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(404)
      end
    end
  end

  describe "POST #accept (atomic accept)" do
    let!(:invite) {
      create(:user_organization_membership_invite,
        organization: organization, invitee_email: invitee_email, inviter: admin_user)
    }

    context "(a) happy path: invitee accepts and lands :active" do
      it "creates :active membership + populates accepted_at + invitee_user_id" do
        sign_in(invitee_user)
        expect {
          post "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/accept"
        }.to change { invitee_user.user_organization_memberships.count }.by(1)

        membership = invitee_user.user_organization_memberships.last
        expect(membership.status).to eq("active")
        expect(membership.organization_id).to eq(organization.id)

        invite.reload
        expect(invite.accepted_at).not_to be_nil
        expect(invite.invitee_user_id).to eq(invitee_user.id)
      end
    end

    context "(c) second-accept blocked" do
      it "returns 422 for JSON callers" do
        sign_in(invitee_user)
        post "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/accept"
        post "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(422)
      end

      it "redirects with flash for HTML callers (Inertia)" do
        sign_in(invitee_user)
        post "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/accept"
        post "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/accept"
        expect(response.status).to eq(303)
        expect(flash[:alert]).to include("already accepted").or include("already activated")
      end
    end

    context "(d) expired-token accept blocked" do
      it "returns 410 for JSON callers (verifier and column layer surface the same status)" do
        # Both InvalidSignature from the verifier and the InviteExpired check
        # on the column end up as :gone.
        invite.update_columns(expires_at: 1.day.ago)
        token = invite.signed_id(purpose: :accept_invite, expires_at: 1.day.ago)
        sign_in(invitee_user)
        post "/organizations/#{organization.id}/membership_invites/#{token}/accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(410)
      end

      it "(WR-10) returns 303 redirect with 'Invitation expired.' flash for HTML callers" do
        invite.update_columns(expires_at: 1.day.ago)
        token = invite.signed_id(purpose: :accept_invite, expires_at: 1.day.ago)
        sign_in(invitee_user)
        post "/organizations/#{organization.id}/membership_invites/#{token}/accept"
        expect(response.status).to eq(303)
        expect(flash[:alert]).to eq("Invitation expired.")
      end
    end

    context "(e) revoked-invite accept blocked" do
      it "returns 422 for JSON callers" do
        invite.update!(revoked_at: Time.current)
        sign_in(invitee_user)
        post "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(422)
      end
    end

    context "(f) signature-tampered token blocked" do
      it "returns 410 for JSON callers (verifier-layer rejection routed through :gone, WR-10)" do
        # As in the confirm_accept case above: a tampered signature and an
        # expired one look the same to the InvalidSignature rescue.
        token = signed_token(invite)
        tampered = token[0..-3] + "ZZ"
        sign_in(invitee_user)
        post "/organizations/#{organization.id}/membership_invites/#{tampered}/accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(410)
      end
    end

    context "(b) non-invitee accept blocked" do
      it "returns 403 for JSON callers" do
        other_user = create(:user, email: "other@example.com").tap { |u| complete_registration_with_active_link(u) }
        sign_in(other_user)
        post "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(403)
      end
    end

    context "(g WR-01) cross-organization URL/invite mismatch on accept" do
      it "returns 404 for JSON when params[:organization_id] differs from invite.organization_id" do
        other_org = create(:organization)
        sign_in(invitee_user)
        post "/organizations/#{other_org.id}/membership_invites/#{signed_token(invite)}/accept",
          headers: {"Accept" => "application/json"}
        expect(response.status).to eq(404)
      end
    end

    context "(WR-04) re-invite of removed user" do
      it "re-activates an existing :removed membership without raising RecordNotUnique" do
        existing = create(:user_organization_membership,
          user: invitee_user, organization: organization, role: :standard, status: :active)
        existing.remove!
        expect(existing.reload.status).to eq("removed")

        sign_in(invitee_user)
        post "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/accept"

        expect(response.status).to eq(303)
        existing.reload
        expect(existing.status).to eq("active")
        expect(invite.reload.accepted_at).not_to be_nil
      end
    end

    context "(WR-06) successful accept redirects with status 303 (See Other)" do
      it "uses :see_other status for Inertia POST→GET" do
        sign_in(invitee_user)
        post "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/accept"
        expect(response.status).to eq(303)
      end
    end

    context "when accepting an existing pending membership by ID" do
      let!(:pending_membership) do
        create(:user_organization_membership,
          user: invitee_user,
          organization: organization,
          status: :pending)
      end

      it "activates the membership and redirects with :see_other for HTML" do
        sign_in(invitee_user)
        expect {
          post "/organizations/#{organization.id}/membership_invites/#{pending_membership.id}/accept"
        }.to change { pending_membership.reload.status }.from("pending").to("active")

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(users_organization_memberships_path)
      end

      it "activates the membership and returns JSON redirect for mobile" do
        raw_token = "test-bearer-#{SecureRandom.hex(8)}"
        ApiKey.create!(bearer: invitee_user, token: raw_token)

        expect {
          post "/organizations/#{organization.id}/membership_invites/#{pending_membership.id}/accept",
            headers: {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}
        }.to change { pending_membership.reload.status }.from("pending").to("active")

        expect(pending_membership.role).to eq("standard")
        expect(response).to have_http_status(:ok)
        expect(response.parsed_body["redirect"]).to eq(users_organization_memberships_path)
      end

      it "rejects a removed member attempting to self-reactivate by numeric membership ID" do
        removed_admin = create(:user, email: "former-admin@example.com").tap do |u|
          complete_registration_with_active_link(u)
        end
        removed_membership = create(
          :user_organization_membership,
          user: removed_admin,
          organization: organization,
          role: :admin,
          status: :active
        )
        removed_membership.remove!
        expect(removed_membership.reload.status).to eq("removed")
        expect(removed_membership.role).to eq("standard")

        sign_in(removed_admin)
        post "/organizations/#{organization.id}/membership_invites/#{removed_membership.id}/accept",
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:not_found)
        removed_membership.reload
        expect(removed_membership.status).to eq("removed")
        expect(removed_membership.role).to eq("standard")
      end
    end

    context "when an active admin accepts a signed invite link for the same organization" do
      it "preserves the admin's existing :admin role instead of demoting to :standard" do
        admin_user.update!(email: "admin-invitee@example.com", is_email_verified: true)
        self_invite = create(
          :user_organization_membership_invite,
          organization: organization,
          invitee_email: "admin-invitee@example.com",
          inviter: admin_user
        )

        sign_in(admin_user)
        post "/organizations/#{organization.id}/membership_invites/#{signed_token(self_invite)}/accept"

        expect(response).to have_http_status(:see_other)
        admin_membership.reload
        expect(admin_membership.status).to eq("active")
        expect(admin_membership.role).to eq("admin")
      end
    end

    context "atomicity" do
      it "rolls back membership creation when invite update fails" do
        sign_in(invitee_user)
        allow_any_instance_of(UserOrganizationMembershipInvite).to receive(:update!).and_raise(ActiveRecord::RecordInvalid)
        expect {
          post "/organizations/#{organization.id}/membership_invites/#{signed_token(invite)}/accept"
        }.not_to change { UserOrganizationMembership.count }
      end
    end
  end

  describe "DELETE #destroy (revoke)" do
    let!(:invite_for_destroy) {
      create(:user_organization_membership_invite,
        organization: organization, invitee_email: invitee_email, inviter: admin_user)
    }

    context "(g part 1) revoke happy path" do
      it "sets revoked_at and returns 204" do
        sign_in(admin_user)
        delete "/organizations/#{organization.id}/membership_invites/#{invite_for_destroy.id}"
        expect(response.status).to eq(204).or eq(200)
        expect(invite_for_destroy.reload.revoked_at).not_to be_nil
      end
    end

    context "(g part 2) revoke idempotency on already-revoked" do
      it "returns 422" do
        invite_for_destroy.update!(revoked_at: Time.current)
        sign_in(admin_user)
        delete "/organizations/#{organization.id}/membership_invites/#{invite_for_destroy.id}"
        expect(response.status).to eq(422)
      end
    end

    context "(g part 3) revoke on already-accepted" do
      it "returns 422 with 'already accepted' message" do
        invite_for_destroy.update!(accepted_at: Time.current, invitee_user_id: invitee_user.id)
        sign_in(admin_user)
        delete "/organizations/#{organization.id}/membership_invites/#{invite_for_destroy.id}"
        expect(response.status).to eq(422)
        expect(response.body).to include("already accepted")
      end
    end

    # Run the shared example against #destroy. It uses the shared example's own
    # `organization`, and the invite is created inside the proc, which runs
    # through instance_exec so it can see that `organization`.
    include_examples "requires organization admin",
      verb: :delete,
      path: -> {
        invite = create(:user_organization_membership_invite,
          organization: organization, invitee_email: "x@example.com")
        "/organizations/#{organization.id}/membership_invites/#{invite.id}"
      }
  end

  describe "POST #create (dual-surface: web Inertia PRG / mobile JSON guard)" do
    context "web (Inertia / cookie) caller" do
      it "creates the invite and redirects back to the members tab (PRG)" do
        sign_in(admin_user)
        expect {
          post "/organizations/#{organization.id}/membership_invites",
            params: {invite: {invitee_email: "fresh@example.com"}}
        }.to change(UserOrganizationMembershipInvite, :count).by(1)
        expect(response).to have_http_status(:redirect)
        expect(response.location).to include("/organizations/#{organization.id}/memberships/")
        expect(response.location).to include("tab=members")
      end

      it "(h) redirects without creating a duplicate when an active invite exists" do
        create(:user_organization_membership_invite,
          organization: organization, invitee_email: invitee_email, inviter: admin_user)
        sign_in(admin_user)
        expect {
          post "/organizations/#{organization.id}/membership_invites",
            params: {invite: {invitee_email: invitee_email}}
        }.not_to change(UserOrganizationMembershipInvite, :count)
        expect(response).to have_http_status(:redirect)
      end

      it "permits a new invite when the prior one is :revoked" do
        prior = create(:user_organization_membership_invite,
          organization: organization, invitee_email: invitee_email, inviter: admin_user)
        prior.update!(revoked_at: Time.current)
        sign_in(admin_user)
        expect {
          post "/organizations/#{organization.id}/membership_invites",
            params: {invite: {invitee_email: invitee_email}}
        }.to change(UserOrganizationMembershipInvite, :count).by(1)
        expect(response).to have_http_status(:redirect)
      end
    end

    # @lat: [[organization-invitation-controller#Organization invitation controller#Creating an invite returns format-specific responses]]
    context "mobile (JSON) caller" do
      it "returns 200 on success" do
        sign_in(admin_user)
        post "/organizations/#{organization.id}/membership_invites",
          params: {invite: {invitee_email: "mobile@example.com"}}, as: :json
        expect(response.status).to eq(200)
      end

      it "returns a 422 validation_failed envelope on an active duplicate" do
        create(:user_organization_membership_invite,
          organization: organization, invitee_email: invitee_email, inviter: admin_user)
        sign_in(admin_user)
        post "/organizations/#{organization.id}/membership_invites",
          params: {invite: {invitee_email: invitee_email}}, as: :json
        expect(response.status).to eq(422)
        # The error shape is { error: { code, message, details: { base: [...] } } }.
        expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
        expect(response.parsed_body.dig("error", "message")).to include("already has an active invite")
        expect(response.parsed_body.dig("error", "details", "base").join).to include("already has an active invite")
      end
    end

    # Run the shared example against #create, with a path proc built from the shared example's `organization`.
    include_examples "requires organization admin",
      verb: :post,
      path: -> { "/organizations/#{organization.id}/membership_invites" },
      params: {invite: {invitee_email: "test@example.com"}}

    context "per-email rate limit normalization" do
      it "shares the rate-limit bucket across whitespace/case variations and normalizes persisted invitee_email" do
        with_rate_limit_enabled(:org_invite) do
          sign_in(admin_user)
          variations = [
            "Victim@Example.com",
            "victim@example.com ",
            "  VICTIM@example.com",
            "victim@Example.COM\n",
            "\tvictim@example.com\t"
          ]

          variations.each do |raw_email|
            post "/organizations/#{organization.id}/membership_invites",
              params: {invite: {invitee_email: raw_email}},
              as: :json
          end

          expect(UserOrganizationMembershipInvite.last&.invitee_email).to eq("victim@example.com")

          post "/organizations/#{organization.id}/membership_invites",
            params: {invite: {invitee_email: "  victim@example.com  "}},
            as: :json
          expect(response).to have_http_status(:too_many_requests)
        end
      end
    end
  end
end
