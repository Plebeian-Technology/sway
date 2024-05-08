class OrganizationsController < ApplicationController
  before_action :verify_is_admin, only: %i[create]

  def index
    render json: Organization.where(sway_locale_id: organization_params[:sway_locale_id]), status: :ok
  end

  def show
    o = Organization.find_by(id: params[:id])
    if o.present?
      render json: o.to_builder.attributes!, status: :ok
    else
      render json: { success: false, message: "Organization not found." }, status: :ok
    end
  end

  def create
    render json: Organization.find_or_create_by(organization_params), status: :ok
  end

  private

  def organization_params
    params.require(:organization).permit(:name, :icon_path, :sway_locale_id)
  end
end
