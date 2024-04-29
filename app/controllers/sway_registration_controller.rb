# typed: true
# frozen_string_literal: true

class RegistrationController < ApplicationController
  def index
    Rails.logger.info 'Render Registration.tsx'

    render inertia: 'Registration', props: {
      user: current_user&.to_builder&.attributes!
    }
  end
end
