# frozen_string_literal: true

require "rails_helper"

# Proves two things about cross-site request forgery protection: the /api/v1 routes
# quietly empty the session rather than blowing up, and a request carrying a bearer
# token skips the forgery check altogether.
RSpec.describe "/api/v1 CSRF behavior", type: :request do
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

  it "cookie POST /user_votes WITHOUT CSRF token is rejected (regression)" do
    sign_in(user)
    post "/user_votes", params: {bill_id: bill.id, support: "FOR"}
    expect(response.status).to eq(422).or eq(403).or eq(302)
    expect(UserVote.count).to eq(0)
  end

  it "bearer POST /user_votes WITHOUT CSRF token succeeds" do
    raw = "api-v1-csrf-#{SecureRandom.hex(8)}"
    ApiKey.create!(bearer: user, token: raw)
    post "/user_votes",
      params: {bill_id: bill.id, support: "FOR"},
      headers: {"Authorization" => "Bearer #{raw}"}
    # Bearer request bypasses CSRF.
    expect(response.status).not_to eq(422)
    expect(response.status).not_to eq(403)
    expect(UserVote.where(user: user, bill_id: bill.id)).to exist
  end

  it "invalid bearer POST /user_votes WITH cookie session STILL enforces CSRF" do
    sign_in(user)
    post "/user_votes",
      params: {bill_id: bill.id, support: "FOR"},
      headers: {"Authorization" => "Bearer invalid-csrf-token"}
    expect(response.status).to eq(422).or eq(403).or eq(302)
    expect(UserVote.count).to eq(0)
  end
end
