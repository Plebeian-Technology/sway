# typed: true
# frozen_string_literal: true

class SwayRegistrationController < ApplicationController
  def index
    Rails.logger.info 'Render Registration.tsx'

    if current_user
      render inertia: 'Registration', props: {
        user: current_user&.to_builder&.attributes!, isBubbles: false
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

    name = T.let(sway_registration_params.fetch(:name), T.nilable(String))
    return if name.blank?

    address = Address.from_string(T.let(sway_registration_params.fetch(:address), T.nilable(String)))
    return if address.nil?

    sway_registration = SwayRegistrationService.new(u, name, address)
  end

  private

  sig { returns(ActionController::Parameters) }
  def sway_registration_params
    params.require(:sway_registration).permit(:name, :address)
  end
end
