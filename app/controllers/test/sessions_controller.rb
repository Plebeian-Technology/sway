# frozen_string_literal: true

class Test::SessionsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :authenticate_sway_user!

  def create
    raise "Test-only route" unless Rails.env.test?

    user = User.find_by(id: params[:user_id])
    return render json: {ok: false}, status: :not_found unless user

    # @lat: [[session-identity-guards#Why Test::SessionsController resets the session before stamping it]]
    reset_session
    session[:user_id] = user.id
    BrowserSession.stamp(session, user)
    render json: {ok: true}
  end
end
