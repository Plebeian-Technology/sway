# frozen_string_literal: true

# @lat: [[query-parameter-navigation-carry#Query parameter navigation carry#Centralized interception mechanism#Server redirect carry follows real form writes]]
class Test::QueryParameterCarryProbeController < ApplicationController
  skip_before_action :is_api_request_and_is_route_api_accessible?
  skip_before_action :authenticate_sway_user!
  skip_before_action :set_sway_locale_id_in_session
  skip_before_action :capture_attribution_param

  def redirect_to_organizations
    redirect_to "/organizations/__query_parameter_carry_target?org_tab=changes"
  end

  def redirect_to_organizations_without_tab
    redirect_to "/organizations/__query_parameter_carry_target"
  end

  def redirect_to_bills
    redirect_to "/bills/__query_parameter_carry_target"
  end

  def redirect_to_bills_with_clear
    redirect_to "/bills/__query_parameter_carry_target?search=&bills_page="
  end

  def redirect_to_bills_with_repeated_clear
    redirect_to "/bills/__query_parameter_carry_target?search=&search=later"
  end

  def redirect_to_creator
    redirect_to "/admin/bill_creator/#{params[:bill_id]}/__query_parameter_carry_target"
  end

  def redirect_to_creator_with_empty_list
    redirect_to "/admin/bill_creator/#{params[:bill_id]}/__query_parameter_carry_target?selected_stages%5B%5D=#summary"
  end

  def redirect_to_excluded_target
    redirect_to "/__query_parameter_carry_target?fixed=target"
  end

  def redirect_to_excluded_destination
    redirect_to "/sessions/__query_parameter_carry_target?fixed=target"
  end

  def redirect_to_location
    response.status = :found
    response.location = params.require(:location)
  end

  def render_conflict
    response.headers["X-Inertia-Location"] = "https://elsewhere.example/path"
    head :conflict
  end

  def show_target
    render plain: request.fullpath
  end
end
