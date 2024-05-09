# typed: true
# frozen_string_literal: true

class SwayRegistrationController < ApplicationController
  extend T::Sig

  skip_before_action :redirect_if_no_current_user

  T::Configuration.inline_type_error_handler = lambda do |error, _opts|
    Rails.logger.error error
  end

  def index
    u = current_user
    if u.nil?
      redirect_to root_path
    elsif u.is_registration_complete
      redirect_to legislators_path
    else
      T.unsafe(self).render_registration
    end
  end

  # Update user's sway registration status
  # Finds representatives based on a user's address
  # creates UserLegislators and initial UserLegislatorScores
  # and sets user.is_registered to true
  def create
    u = current_user
    if u.nil?
      T.unsafe(self).route_home
    elsif u.has_user_legislators?
      T.unsafe(self).route_legislators
    else
      T.cast(user_address(u).address, Address).sway_locales.each do |sway_locale|
        SwayRegistrationService.new(u, T.cast(user_address(u).address, Address), sway_locale).run
      end

      if u.is_registration_complete
        T.unsafe(self).route_legislators
        # redirect_to legislators_path
      else
        T.unsafe(self).route_registration
      end
    end
  end

  private

  sig { params(u: User).returns(UserAddress) }
  def user_address(u)
    u.user_address || UserAddress.find_or_create_by(user: u, address:)
  end

  sig { returns(Address) }
  def address
    Address.find_or_create_by!(
      street: sway_registration_params.fetch(:street),
      city: sway_registration_params.fetch(:city),
      region_code: sway_registration_params.fetch(:regionCode),
      postal_code: sway_registration_params.fetch(:postalCode),
      country: sway_registration_params.fetch(:country),
      latitude: sway_registration_params.fetch(:latitude),
      longitude: sway_registration_params.fetch(:longitude)
    )
  end

  sig { returns(ActionController::Parameters) }
  def sway_registration_params
    params.require(:sway_registration).permit(:latitude, :longitude, :street, :city, :region, :regionCode,
                                              :postalCode, :country)
  end
end
