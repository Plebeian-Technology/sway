# frozen_string_literal: true

# @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Signing out every browser]]
module BrowserSession
  def self.stamp(session, user)
    session[:auth_identity] = user.created_at&.to_i
    session[:session_generation] = user.session_generation
  end

  def self.current?(session, user)
    auth_identity = session[:auth_identity]
    return false if auth_identity.present? && auth_identity.to_i != user.created_at.to_i

    session[:session_generation].to_i == user.session_generation
  end

  def self.forget(session)
    session.delete(:user_id)
    session.delete(:auth_identity)
    session.delete(:session_generation)
  end
end
