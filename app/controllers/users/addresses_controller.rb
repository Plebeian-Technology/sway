# frozen_string_literal: true

module Users
  # @lat: [[web-profile-page#Web profile page#Changing the address from the web]]
  class AddressesController < ApplicationController
    def edit
      render inertia: Pages::REGISTRATION, props: {
        change_address: true,
        current_address: current_address,
        registration_outcome: registration_outcome
      }.compact
    end

    private

    def current_address
      address = current_user.address
      return nil if address.nil?

      [address.street, address.city, address.region_code, address.postal_code, address.country]
        .filter_map(&:presence).join(", ")
    end

    def registration_outcome
      outcome = flash[:registration_outcome]
      RegistrationOutcomeResource.new(outcome.symbolize_keys).serializable_hash if outcome.present?
    end
  end
end
