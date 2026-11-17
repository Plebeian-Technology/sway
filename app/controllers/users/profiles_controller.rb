# frozen_string_literal: true

module Users
  class ProfilesController < ApplicationController
    before_action :authenticate_sway_user!

    def show
      render inertia: "users/Profile", props: {
        user: current_user.slice(:id, :email, :full_name, :created_at),
        address: current_user.user_address&.address&.to_builder&.serializable_hash,
        is_api_user: current_user.is_sway_api_user?
      }
    end
  end
end
