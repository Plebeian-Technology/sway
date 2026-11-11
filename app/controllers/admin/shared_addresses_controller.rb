# frozen_string_literal: true

module Admin
  class SharedAddressesController < ApplicationController
    before_action :verify_is_sway_admin

    def show
      render inertia: Pages::ADMIN_SHARED_ADDRESSES, props: {shared_addresses: SharedAddressCountsService.rows}
    end
  end
end
