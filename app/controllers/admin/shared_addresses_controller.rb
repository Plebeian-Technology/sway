# frozen_string_literal: true

# @lat: [[mobile-admin-area#The shared addresses screen]]
module Admin
  class SharedAddressesController < ApplicationController
    before_action :verify_is_sway_admin

    def show
      render_inertia_or_json(page: Pages::ADMIN_SHARED_ADDRESSES, props: {shared_addresses: SharedAddressCountsService.rows})
    end
  end
end
