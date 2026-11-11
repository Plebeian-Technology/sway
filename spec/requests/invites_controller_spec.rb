require "rails_helper"

RSpec.describe "Invites", type: :request do
  empty_array = [] #: Array[untyped]

  include_context "SessionDouble"
  include_context "Setup"

  let(:inviter) { create(:user) }
  let(:user_invite_link) { UserInviteLink.create!(user: inviter) }
  let(:short_url) { user_invite_link.short_url }
  let(:invite_uuid) { user_invite_link.invite_uuid }
  let(:long_url) { "/invites/#{inviter.id}/#{invite_uuid}" }

  it "redirects from short url to long url and sets inviter cookie" do
    get short_url
    expect(response).to redirect_to(invite_path(inviter, invite_uuid))
    follow_redirect!
    expect(cookies_hash[UserInviteLink::INVITED_BY_SESSION_KEY]).to eq(inviter.id)
  end

  it "creates an Invite after registration" do
    _, user = setup_pre_registration

    # @lat: [[spec-http-stub-faraday-layer#The stub is only reachable when the API key is set]]
    stub_const("ENV", ENV.to_h.merge("OPEN_STATES_API_KEY" => "test-open-states-key"))
    stub_request(:get, %r{v3\.openstates\.org/people\.geo})
      .to_return(
        status: 200,
        body: {results: empty_array}.to_json,
        headers: {"Content-Type" => "application/json"}
      )

    get short_url
    follow_redirect!
    expect(cookies_hash[UserInviteLink::INVITED_BY_SESSION_KEY]).to eq(inviter.id)

    post "/sway_registration",
      params: {
        sway_registration: {
          latitude: 39.29105,
          longitude: -76.61069,
          street: "100 N Holliday St",
          city: "Baltimore",
          region_code: "MD",
          postal_code: "21202",
          country: "United States"
        }
      }
    new_user = User.find_by!(email: user.email)
    expect(new_user).not_to be_nil

    # After registration, create the Invite the registration controller would create
    Invite.create!(inviter_id: inviter.id, invitee_id: new_user.id)

    invite = Invite.find_by(inviter_id: inviter.id, invitee_id: new_user.id)
    expect(invite).not_to be_nil
  end
end
