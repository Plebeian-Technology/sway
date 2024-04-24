# typed: true

class ApplicationController < ActionController::Base
  extend T::Sig

  helper_method :current_user

  private

  sig { params(user: T.nilable(User)).returns(T.untyped) }
  def sign_in(user)
    return unless user.present?

    session[:user_id] = user.id
    user.sign_in_count = user.sign_in_count + 1
    user.last_sign_in_at = user.current_sign_in_at
    user.current_sign_in_at = Time.zone.now
    user.last_sign_in_ip = user.current_sign_in_ip
    user.current_sign_in_ip = request.remote_ip
    user.save
  end

  def sign_out
    session[:user_id] = nil
  end

  sig { returns(T.nilable(User)) }
  def current_user
    @current_user ||=
      (User.find_by(id: session[:user_id]) if session[:user_id])
  end

  def relying_party
    @relying_party ||=
      WebAuthn::RelyingParty.new(
        origin: 'https://localhost:3000',
        name: 'sway'
      )
  end
end
