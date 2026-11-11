# frozen_string_literal: true

require "rails_helper"

# @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
RSpec.describe "CSRF enforcement regression (H1 fix)", type: :request do
  include_context "Setup"

  around do |ex|
    orig = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    ex.run
    ActionController::Base.allow_forgery_protection = orig
  end

  let!(:sway_and_user) { setup }
  let(:sway_locale) { sway_and_user.first }
  let(:user) { sway_and_user.last }
  let(:bill) { create(:bill, sway_locale: sway_locale) }

  it "cookie POST without CSRF token is rejected (CSRF still enforced)" do
    sign_in(user)
    post "/user_votes", params: {bill_id: bill.id, support: "FOR"}
    # ApplicationController catches InvalidAuthenticityToken and turns it into
    # a redirect; without that rescue it would be a 422. Either is fine here —
    # what matters is the request did NOT go through, so no UserVote exists.
    expect(response.status).to eq(422).or eq(403).or eq(302)
    expect(UserVote.count).to eq(0)
  end

  it "cookie POST with Accept: application/json but NO bearer header STILL enforces CSRF" do
    sign_in(user)
    post "/user_votes",
      params: {bill_id: bill.id, support: "FOR"},
      headers: {"Accept" => "application/json"}
    expect(response.status).to eq(422).or eq(403).or eq(302)
    expect(UserVote.count).to eq(0)
  end

  it "bearer POST without CSRF token succeeds (request-scoped skip)" do
    raw = "csrf-bearer-#{SecureRandom.hex(8)}"
    ApiKey.create!(bearer: user, token: raw)
    post "/user_votes",
      params: {bill_id: bill.id, support: "FOR"},
      headers: {"Authorization" => "Bearer #{raw}"}
    # A bearer token skips the CSRF check, so this must not be turned away.
    expect(response.status).not_to eq(422)
    expect(response.status).not_to eq(403)
    # And the vote actually persisted.
    expect(UserVote.where(user: user, bill_id: bill.id)).to exist
  end

  it "ApplicationController class state is NOT mutated after a bearer request" do
    raw = "csrf-bearer-#{SecureRandom.hex(8)}"
    ApiKey.create!(bearer: user, token: raw)

    # Send the bearer request first. The rejected design, which did
    # `self.class.allow_forgery_protection = false`, would have flipped the
    # class-wide setting right here.
    post "/user_votes",
      params: {bill_id: bill.id, support: "FOR"},
      headers: {"Authorization" => "Bearer #{raw}"}

    # Class state must be unchanged.
    expect(ApplicationController.allow_forgery_protection).to be_truthy

    # A cookie request made after the bearer request must STILL be rejected,
    # which shows the skip applied to that one request only.
    sign_in(user)
    bill_two = create(:bill, sway_locale: sway_locale)
    post "/user_votes", params: {bill_id: bill_two.id, support: "FOR"}
    expect(response.status).to eq(422).or eq(403).or eq(302)
    expect(UserVote.where(bill_id: bill_two.id)).not_to exist
  end

  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#A refused CSRF write leaves a fresh retry path]]
  describe "what an expired page tells the browser" do
    before do
      sign_in(user)
      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Referer" => "/bills/#{bill.id}"}
    end

    # registerFlashToasts renders flash.notice at SUCCESS level, so the refusal
    # used to arrive as a GREEN "The page expired, please try again."
    it "says it as an alert, not as a notice" do
      expect(flash[:alert]).to eq("The page expired, please try again.")
      expect(flash[:notice]).to be_nil
    end

    # The machine-readable half, and a FLAG rather than the sentence: a handler
    # matching on the message text would work today and stop firing the first
    # time somebody reworded it, while still looking like it passed. Read by
    # app/frontend/sway_utils/pageExpired.ts.
    it "flags the refusal so a write handler can see it without reading the sentence" do
      expect(flash[:page_expired]).to be(true)
    end

    # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#A refused CSRF write leaves a fresh retry path]]
    it "hands the browser a fresh token on the page it redirects to" do
      follow_redirect!

      expect(response.cookies["XSRF-TOKEN"]).to be_present
    end

    it "lets the browser write again without reloading the page" do
      follow_redirect!
      token = response.cookies["XSRF-TOKEN"]

      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"X-CSRF-Token" => token}

      expect(response.status).not_to eq(422)
      expect(response.status).not_to eq(403)
      expect(UserVote.where(user: user, bill_id: bill.id)).to exist
    end
  end

  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens]]
  describe "authoritative API tokens on shared routes" do
    let(:user_b) { create(:user).tap { |u| complete_registration_with_active_link(u) } }

    it "invalid bearer token with ambient cookie session fails closed and enforces CSRF" do
      sign_in(user)
      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Authorization" => "Bearer invalid-review-token"}

      expect(response.status).to eq(422).or eq(403).or eq(302)
      expect(UserVote.count).to eq(0)
    end

    it "invalid bearer token with ambient cookie session and valid CSRF token still rejects request (fails closed)" do
      sign_in(user)
      get "/bills/#{bill.id}"
      token = response.cookies["XSRF-TOKEN"]

      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Authorization" => "Bearer invalid-review-token", "X-CSRF-Token" => token}

      expect(response.status).to eq(401).or eq(302)
      expect(UserVote.count).to eq(0)
    end

    it "expired bearer token with ambient cookie session fails closed and enforces CSRF" do
      expired_token = "expired-bearer-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user, token: expired_token, expires_at: 1.day.ago)

      sign_in(user)
      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Authorization" => "Bearer #{expired_token}"}

      expect(response.status).to eq(422).or eq(403).or eq(302)
      expect(UserVote.count).to eq(0)
    end

    it "revoked bearer token with ambient cookie session fails closed and enforces CSRF" do
      device = create(:user_device, user: user)
      revoked_token = "revoked-bearer-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user, user_device: device, token: revoked_token)
      device.revoke!

      sign_in(user)
      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Authorization" => "Bearer #{revoked_token}"}

      expect(response.status).to eq(422).or eq(403).or eq(302)
      expect(UserVote.count).to eq(0)
    end

    it "empty or malformed bearer token with ambient cookie session fails closed and enforces CSRF" do
      sign_in(user)

      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Authorization" => "Bearer"}

      expect(response.status).to eq(422).or eq(403).or eq(302)
      expect(UserVote.count).to eq(0)

      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Authorization" => "Bearer "}

      expect(response.status).to eq(422).or eq(403).or eq(302)
      expect(UserVote.count).to eq(0)
    end

    it "valid bearer token for User B operates strictly as User B even when ambient cookie for User A is present" do
      sign_in(user)
      raw_token_b = "token-b-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user_b, token: raw_token_b)

      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Authorization" => "Bearer #{raw_token_b}"}

      expect(response.status).not_to eq(422)
      expect(response.status).not_to eq(403)
      expect(UserVote.where(user: user_b, bill_id: bill.id)).to exist
      expect(UserVote.where(user: user, bill_id: bill.id)).not_to exist
    end

    it "valid legacy Token scheme for User B operates strictly as User B even when ambient cookie for User A is present" do
      sign_in(user)
      get "/bills/#{bill.id}"
      token = response.cookies["XSRF-TOKEN"]
      raw_token_b = "token-b-#{SecureRandom.hex(8)}"
      ApiKey.create!(bearer: user_b, token: raw_token_b)

      post "/user_votes",
        params: {bill_id: bill.id, support: "FOR"},
        headers: {"Authorization" => "Token token=\"#{raw_token_b}\"", "X-CSRF-Token" => token}

      expect(response.status).not_to eq(422)
      expect(response.status).not_to eq(403)
      expect(UserVote.where(user: user_b, bill_id: bill.id)).to exist
      expect(UserVote.where(user: user, bill_id: bill.id)).not_to exist
    end
  end
end
