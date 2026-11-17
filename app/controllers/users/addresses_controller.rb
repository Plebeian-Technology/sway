# frozen_string_literal: true

module Users
  class AddressesController < ApplicationController
    include AddressSwitching

    before_action :authenticate_sway_user!

    def edit
      puts "AddressEdit reached. User: #{current_user&.id}"
      render inertia: "users/AddressEdit", props: {
        address: current_user.user_address&.address&.to_builder&.serializable_hash
      }
    end

    def update
      # TODO: Implement update logic reusing UserAddressSwitchService
      render json: {message: "Not implemented yet"}
    end
  end
end
