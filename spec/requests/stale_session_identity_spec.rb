require "rails_helper"

# @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
RSpec.describe "Stale session identity guard", type: :request do
  include_context "SessionDouble"

  let(:user) { create(:user, is_registration_complete: false) }

  it "marks history for clearing when a refresh token restores the session" do
    refresh = create(:refresh_token, user: user)
    cookies_hash[:refresh_token] = refresh.token
    allow_any_instance_of(RefreshToken).to receive(:usable_for?).and_return(true)

    get sway_registration_index_path, headers: {"X-Inertia" => "true", "X-Inertia-Version" => InertiaRails.configuration.version.to_s, "User-Agent" => "RSpec Browser"}

    expect(session_hash[:user_id]).to eq(user.id)
    expect(response).to have_http_status(:ok)
    expect(response.parsed_body["clearHistory"]).to be true
    expect(inertia).to render_component(Pages::REGISTRATION)
    expect(inertia).to have_props { |props| props.dig("user", "id") == user.id }
  end

  it "signs out a session whose stored identity no longer matches the user id (simulated db:reset)" do
    sign_in(user)
    session_hash[:auth_identity] = user.created_at.to_i - 99_999

    get "/legislators", headers: {"Accept" => "application/json"}

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body.dig("error", "code")).to eq("unauthenticated")
  end

  it "keeps the session authenticated when the stored identity matches" do
    sign_in(user)
    session_hash[:auth_identity] = user.created_at.to_i

    get "/legislators", headers: {"Accept" => "application/json"}

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig("error", "code")).to eq("registration_incomplete")
  end

  it "does NOT sign out a pre-existing session that has no stored identity (backward compat)" do
    sign_in(user)
    session_hash.delete(:auth_identity)

    get "/legislators", headers: {"Accept" => "application/json"}

    expect(response).to have_http_status(:forbidden)
    expect(response.parsed_body.dig("error", "code")).to eq("registration_incomplete")
    expect(session_hash[:auth_identity]).to eq(user.created_at.to_i)
  end
end

[false, true].each do |with_session_double|
  RSpec.describe "Switching request-spec users (SessionDouble: #{with_session_double})", type: :request do
    include_context "SessionDouble" if with_session_double

    # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Request specs switch the complete authentication identity]]
    it "authenticates the next user when account creation times differ" do
      first_user = create(:user, created_at: Time.utc(2026, 1, 1))
      next_user = create(:user, created_at: Time.utc(2026, 1, 2))
      sign_in(first_user)
      get "/legislators", headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:forbidden)

      sign_in(next_user)
      get "/legislators", headers: {"Accept" => "application/json"}
      expect(response).to have_http_status(:forbidden)
      expect(response.parsed_body.dig("error", "code")).to eq("registration_incomplete")
    end
  end
end
