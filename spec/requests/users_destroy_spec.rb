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

    it "destroys organization bill position changes authored by the user" do
      position_change = create(:organization_bill_position_change, updated_by: user)

      delete "/users/#{user.id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:no_content)
      expect(OrganizationBillPositionChange.exists?(position_change.id)).to be(false)
    end

    it "nullifies approved_by_id on position changes approved by the user" do
      position_change = create(:organization_bill_position_change, approved_by: user, status: :approved)

      delete "/users/#{user.id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:no_content)
      expect(position_change.reload.approved_by_id).to be_nil
    end

    it "nullifies rejected_by_id on position changes rejected by the user" do
      position_change = create(:organization_bill_position_change, rejected_by: user, status: :rejected, rejected_at: Time.current)

      delete "/users/#{user.id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:no_content)
      expect(position_change.reload.rejected_by_id).to be_nil
    end

    it "cascades historical score explanations when user is deleted" do
      skip "historical_score_explanations table not present" unless ActiveRecord::Base.connection.table_exists?(:historical_score_explanations)

      explanation = create(:historical_score_explanation, user: user)

      delete "/users/#{user.id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:no_content)
      expect(HistoricalScoreExplanation.exists?(explanation.id)).to be(false)
    end

    it "cascades historical repair deliveries when user is deleted" do
      conn = ActiveRecord::Base.connection
      skip "historical_repair_deliveries table not present" unless conn.table_exists?(:historical_repair_deliveries)

      locale = create(:sway_locale)
      dedup = "dedup-#{SecureRandom.hex(8)}"
      conn.execute(
        "INSERT INTO historical_repair_candidates (sway_locale_id, candidate_type, target_type, target_id, deduplication_key, current_values, proposed_values, status, version, created_at, updated_at) " \
        "VALUES (#{locale.id}, 'legislator_vote', 'Legislator', 1, '#{dedup}', '{}', '{}', 'unapplied', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
      )
      candidate_id = conn.select_value("SELECT last_insert_rowid()")
      token = "tok-#{SecureRandom.hex(8)}"
      conn.execute(
        "INSERT INTO historical_repair_previews (historical_repair_candidate_id, preview_token, calculation_status, status, created_at, updated_at) " \
        "VALUES (#{candidate_id}, '#{token}', 'ready_for_review', 'previewed', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
      )
      preview_id = conn.select_value("SELECT last_insert_rowid()")

      conn.execute(
        "INSERT INTO historical_repair_deliveries (historical_repair_candidate_id, historical_repair_preview_id, user_id, channel, status, created_at, updated_at) " \
        "VALUES (#{candidate_id}, #{preview_id}, #{user.id}, 'sms', 'pending', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)"
      )
      delivery_id = conn.select_value("SELECT last_insert_rowid()")

      delete "/users/#{user.id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:no_content)
      count = conn.select_value("SELECT COUNT(*) FROM historical_repair_deliveries WHERE id = #{delivery_id}")
      expect(count).to eq(0)
    end

    it "destroys registration funnel events linked to the user" do
      event = RegistrationFunnelEvent.create!(user: user, step: :landing, visitor_token: SecureRandom.uuid)

      delete "/users/#{user.id}", headers: {"Authorization" => "Bearer #{raw_token}"}

      expect(response).to have_http_status(:no_content)
      expect(RegistrationFunnelEvent.exists?(event.id)).to be(false)
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
