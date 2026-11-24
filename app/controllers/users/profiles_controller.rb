# frozen_string_literal: true

module Users
  # @lat: [[web-profile-page#Web profile page]]
  class ProfilesController < ApplicationController
    def show
      render inertia: Pages::PROFILE
    end
  end
end
