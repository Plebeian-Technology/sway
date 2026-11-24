# frozen_string_literal: true

require "rails_helper"

# @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Signing out every browser]]
RSpec.describe "POST /users/sign_out_all_devices", type: :request do
  let(:user) { create(:user).tap { |u| complete_registration_with_active_link(u) } }

  def browser_signed_in_as(person)
    open_session.tap do |browser|
      browser.post "/test/sessions", params: {user_id: person.id}
      expect(browser.response.parsed_body).to eq("ok" => true)
    end
  end

  def signed_in?(browser, headers: {})
    browser.get "/profile", headers: headers
    browser.response.successful?
  end

  def encrypted_cookie(name, value)
    jar = ActionDispatch::Request.new(Rails.application.env_config.deep_dup).cookie_jar
    jar.encrypted[name] = value
    jar[name]
  end

  def bearer_token_for(person)
    raw_token = SecureRandom.hex(16)
    ApiKey.create!(name: "mobile", token: raw_token, bearer: person, user_device: create(:user_device, user: person))
    raw_token
  end

  def bearer_accepted?(raw_token)
    get "/users/passkeys", headers: {"Authorization" => "Bearer #{raw_token}", "Accept" => "application/json"}
    response.successful?
  end

  it "signs out the calling browser and lands it on the public home page" do
    caller = browser_signed_in_as(user)

    caller.post "/users/sign_out_all_devices"

    expect(caller.response).to have_http_status(:redirect)
    expect(URI(caller.response.location).path).to eq(root_path)
    expect(caller.flash[:notice]).to eq(UsersController::SIGNED_OUT_ALL_DEVICES_NOTICE)
    expect(signed_in?(caller)).to be(false)
  end

  it "treats another browser of the same user as signed out" do
    caller = browser_signed_in_as(user)
    other_browser = browser_signed_in_as(user)
    expect(signed_in?(other_browser)).to be(true)

    caller.post "/users/sign_out_all_devices"

    expect(signed_in?(other_browser)).to be(false)
  end

  it "keeps another browser holding a refresh-token cookie from signing itself back in" do
    caller = browser_signed_in_as(user)
    other_browser = open_session
    agent = {"User-Agent" => "Second Browser"}
    refresh_token = RefreshToken.create!(
      user: user, token: "other-browser-refresh", ip_address: "127.0.0.1",
      user_agent: agent["User-Agent"], expires_at: 1.year.from_now
    )
    other_browser.cookies[:refresh_token] = encrypted_cookie(:refresh_token, refresh_token.token)
    expect(signed_in?(other_browser, headers: agent)).to be(true)

    caller.post "/users/sign_out_all_devices"

    expect(RefreshToken.where(user_id: user.id)).to be_empty
    expect(signed_in?(other_browser, headers: agent)).to be(false)
  end

  it "rejects the user's mobile bearer tokens" do
    raw_token = bearer_token_for(user)
    expect(bearer_accepted?(raw_token)).to be(true)

    browser_signed_in_as(user).post "/users/sign_out_all_devices"

    expect(bearer_accepted?(raw_token)).to be(false)
  end

  it "leaves another user's browser and bearer tokens signed in" do
    someone_else = create(:user).tap { |u| complete_registration_with_active_link(u) }
    their_browser = browser_signed_in_as(someone_else)
    their_token = bearer_token_for(someone_else)

    browser_signed_in_as(user).post "/users/sign_out_all_devices"

    expect(signed_in?(their_browser)).to be(true)
    expect(bearer_accepted?(their_token)).to be(true)
    expect(someone_else.reload.session_generation).to eq(0)
  end

  it "refuses a request without a valid CSRF token" do
    caller = browser_signed_in_as(user)
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true

    begin
      caller.post "/users/sign_out_all_devices"
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    expect(user.reload.session_generation).to eq(0)
    expect(signed_in?(caller)).to be(true)
  end

  describe "a session written before the generation existed" do
    include_context "SessionDouble"

    it "still authenticates while the user's generation is 0 and is refused after the first increment" do
      session_hash[:user_id] = user.id
      session_hash[:auth_identity] = user.created_at.to_i

      get "/profile"
      expect(response).to have_http_status(:ok)
      expect(session_hash).not_to have_key(:session_generation)

      user.sign_out_all_devices!

      get "/profile"
      expect(response).to redirect_to(root_url)
    end
  end
end
