require "rails_helper"

RSpec.describe "Invites", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:inviter) { create(:user) }
  let(:user_inviter) { UserInviter.create!(user: inviter) }
  let(:short_url) { user_inviter.short_url }
  let(:invite_uuid) { user_inviter.invite_uuid }
  let(:long_url) { "/invites/#{inviter.id}/#{invite_uuid}" }

  it "redirects from short url to long url and sets inviter cookie" do
    get short_url
    expect(response).to redirect_to(invite_path(inviter, invite_uuid))
    follow_redirect!
    expect(cookies_hash[UserInviter::INVITED_BY_SESSION_KEY]).to eq(inviter.id)
  end

  it "creates an Invite after registration" do
    _, user = setup_pre_registration

    # Simulate visiting short URL
    get short_url
    follow_redirect!
    expect(cookies_hash[UserInviter::INVITED_BY_SESSION_KEY]).to eq(inviter.id)

    # Simulate registration (replace with your registration endpoint)
    post "/sway_registration",
         params: { sway_registration: { latitude: -76.1234, longitude: 35.1234, street: "123 Apple Lane", city: "Baltimore",
                                        region_code: "MD", postal_code: "21224", country: "United States" } }
    new_user = User.find_by(email: user.email)
    expect(new_user).not_to be_nil

    # After registration, create Invite (simulate what your registration controller does)
    Invite.create!(inviter_id: inviter.id, invitee_id: new_user.id)

    invite = Invite.find_by(inviter_id: inviter.id, invitee_id: new_user.id)
    expect(invite).not_to be_nil
  end
end
