# frozen_string_literal: true

# @lat: [[public-marketing-and-meta-pages#Why MetaController's pages skip the sign-in and API-route checks]]
class MetaController < ApplicationController
  skip_before_action :authenticate_sway_user!
  skip_before_action :is_api_request_and_is_route_api_accessible?

  def version
    # @lat: [[release-shared-prop#The release prop is shared across pages]]
    render inertia: Pages::VERSION
  end

  def licenses
    render inertia: Pages::LICENSES, props: {licenses: OpenSourceLicensesService.call}
  end
end
