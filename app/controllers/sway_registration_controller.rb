# typed: true
# frozen_string_literal: true

class SwayRegistrationController < ApplicationController
  def index
    Rails.logger.info 'Render Registration.tsx'
    u = current_user

    if u
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
    return if u.nil?

    address = Address.new(
      street: sway_registration_params.fetch(:street),
      city: sway_registration_params.fetch(:city),
      region_code: sway_registration_params.fetch(:regionCode),
      postal_code: sway_registration_params.fetch(:postalCode),
      country: sway_registration_params.fetch(:country),
      latitude: sway_registration_params.fetch(:latitude),
      longitude: sway_registration_params.fetch(:longitude)
    )
    address.save!

    user_legislators = SwayRegistrationService.new(u, address).build_user_legislators

    if user_legislators.empty?
      render inertia: 'Registration', props: {
        success: false, message: 'Failed to create legislators for you.', data: {
          user: current_user&.to_builder&.attributes!, isBubbles: false
        }
      }
    else
      render inertia: 'Legislators', props: {
        user: current_user&.to_builder&.attributes!, legislators: user_legislators.map do |ul|
          T.cast(ul.legislator, Legislator).attributes
        end
      }
    end
  end

  private

  sig { returns(ActionController::Parameters) }
  def sway_registration_params
    params.require(:sway_registration).permit(:latitude, :longitude, :street, :city, :region, :regionCode,
                                              :postalCode, :country)
  end
end
