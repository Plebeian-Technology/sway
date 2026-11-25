# frozen_string_literal: true

module Users
  # @lat: [[web-profile-page#Web profile page#Changing the address from the web]]
  class AddressesController < ApplicationController
    def edit
      render inertia: Pages::REGISTRATION, props: {
        change_address: true,
        current_address: current_user.address&.full_address,
        registration_outcome: registration_outcome
      }.compact
    end

    private

    def registration_outcome
      outcome = flash[:registration_outcome]
      RegistrationOutcomeResource.new(outcome.symbolize_keys).serializable_hash if outcome.present?
    end
  end
end
