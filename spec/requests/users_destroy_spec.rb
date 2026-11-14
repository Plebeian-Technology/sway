# frozen_string_literal: true

require "rails_helper"

# The mobile app's DeleteAccountScreen sends DELETE /users/:id, which the App
# Store requires so people can delete their accounts. This route has to exist:
# without it the request falls through to a GET-only catch-all and 404s.
RSpec.describe "DELETE /users/:id", type: :request do
  describe "bearer/mobile caller" do
    let(:user) do
      create(:user).tap { |u| complete_registration_with_active_link(u) }
    end
    let(:raw_token) { "test-bearer-#{SecureRandom.hex(8)}" }
    let!(:api_key) { ApiKey.create!(bearer: user, token: raw_token) }

    it "deletes the caller's own account and cascades dependents" do
      user_id = user.id
      create(:user_device, user: user, platform: "ios", push_token: "tok")

      delete "/users/#{user_id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:no_content)
      expect(User.exists?(user_id)).to be(false)
      expect(ApiKey.where(bearer_id: user_id, bearer_type: "User")).to be_empty
      expect(UserDevice.where(user_id: user_id)).to be_empty
    end

    it "destroys invites where the user is the inviter" do
      invitee = create(:user)
      invite = Invite.create!(inviter: user, invitee: invitee)

      delete "/users/#{user.id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:no_content)
      expect(Invite.exists?(invite.id)).to be(false)
    end

    it "destroys invites where the user is the invitee" do
      inviter = create(:user)
      invite = Invite.create!(inviter: inviter, invitee: user)

      delete "/users/#{user.id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:no_content)
      expect(Invite.exists?(invite.id)).to be(false)
    end

    it "destroys organization invites sent by the user" do
      org = create(:organization)
      invite = create(:user_organization_membership_invite, inviter: user, organization: org)

      delete "/users/#{user.id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:no_content)
      expect(UserOrganizationMembershipInvite.exists?(invite.id)).to be(false)
    end

    it "refuses to delete another user's account (403) and persists both" do
      other = create(:user).tap { |u| complete_registration_with_active_link(u) }

      delete "/users/#{other.id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:forbidden)
      expect(User.exists?(user.id)).to be(true)
      expect(User.exists?(other.id)).to be(true)
    end
  end

  describe "cookie-session web caller" do
    include_context "SessionDouble"

    let(:user) do
      create(:user).tap { |u| complete_registration_with_active_link(u) }
    end

    it "deletes own account and redirects to root" do
      sign_in(user)
      user_id = user.id

      delete "/users/#{user_id}"

      expect(response).to redirect_to(root_path)
      expect(User.exists?(user_id)).to be(false)
    end

    # @lat: [[client-caches-and-identity#Why sign-out does not clear them by itself]]
    it "signals Inertia to clear browser history, as an ordinary sign-out does" do
      sign_in(user)

      delete "/users/#{user.id}"

      expect(session_hash[:inertia_clear_history]).to be true
    end
  end
end
