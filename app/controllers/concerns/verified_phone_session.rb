# frozen_string_literal: true

# @lat: [[identity-and-access#Identity and access#The phone number is the account#First-passkey enrollment]]
module VerifiedPhoneSession
  extend ActiveSupport::Concern

  VERIFIED_PHONE_WINDOW = 30.minutes

  private

  def remember_verified_phone(phone)
    session[:verified_phone] = phone
    session[:verified_phone_at] = Time.current.to_i
  end

  def verified_phone_current?(phone)
    verified_at = session[:verified_phone_at]
    phone.present? &&
      session[:verified_phone] == phone &&
      verified_at.present? &&
      Time.zone.at(verified_at.to_i) > VERIFIED_PHONE_WINDOW.ago
  end
end
