# typed: true
# frozen_string_literal: true

class SwayRegistrationController < ApplicationController
  extend T::Sig

  T::Configuration.inline_type_error_handler = lambda do |error, opts|
    Rails.logger.error error
  end

  def index
    u = current_user

    if !u.nil? && !u.user_legislators.nil? & u.user_legislators.present?
      render_legislators T.cast(T.cast(u, User).user_legislators, T::Array[T.untyped])
    elsif u.present?
      Rails.logger.info 'Render Registration.tsx'
      render inertia: 'Registration', props: {
        user: u.to_builder.attributes!, isBubbles: false
      }
    else
      redirect_to root_path
    end
  end

  # Update user's sway registration status
  # Finds representatives based on a user's address
  # creates UserLegislators and initial UserLegislatorScores
  # and sets user.is_registered to true
  def create
    u = current_user
    if u.nil?
      redirect_to root_path
    elsif u.has_user_legislators?
      render_legislators T.cast(u.user_legislators, T::Array[UserLegislator])
    else
      user_legislators = SwayRegistrationService.new(u, T.cast(user_address(u).address, Address)).run

      if user_legislators.empty?
        Rails.logger.info('Render Registration.tsx')
        render inertia: 'Registration', props: {
          success: false, message: 'Failed to create legislators for you.', data: {
            user: current_user&.to_builder&.attributes!, isBubbles: false
          }
        }
      else
        render_legislators user_legislators
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

  sig do
    params(user_legislators: T::Array[UserLegislator]).returns(T.untyped)
  end
  def render_legislators(user_legislators)
    Rails.logger.info('Render Legislators.tsx')
    redirect_to legislators_path
  end
end
