# frozen_string_literal: true

module Users
  # @lat: [[web-profile-page#Web profile page]]
  class ProfilesController < ApplicationController
    def show
      render inertia: Pages::PROFILE, props: {
        can_manage_api_keys: current_user.is_sway_api_user?
      }
    end
  end
end
