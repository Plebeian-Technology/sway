# frozen_string_literal: true

RSpec.describe '/s', type: :request do
  describe 'GET /:id' do
    context 'with valid shortened url id' do
      it 'redirects to the invites controller' do
        user = create(:user)

        get "/s/#{user.user_inviter.shortened_urls.first.unique_key}"
        follow_redirect!

        expect(response).to have_http_status(301)
        expect(response.redirect_url).to eq("https://#{response.request.host}/invites/#{user.id}/#{user.user_inviter.invite_uuid}")

        get response.redirect_url
        follow_redirect!

        expect(session[UserInviter::INVITED_BY_SESSION_KEY]).to eq(user.id)
      end
    end
  end
end
