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
  end
end
