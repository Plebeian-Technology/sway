class OrganizationsController < ApplicationController
  before_action :verify_is_admin, only: %i[create update]

  def index
    render json: Organization.where(sway_locale_id: current_sway_locale&.id).map { |o|
                   o.to_builder(with_positions: false).attributes!
                 }, status: :ok
  end

  def show
    o = Organization.find_by(id: params[:id])
    if o.present?
      render json: o.to_builder(with_positions: true).attributes!, status: :ok
    else
      render json: { success: false, message: 'Organization not found.' }, status: :ok
    end
  end

  def create
    render json: Organization.find_or_create_by!(**organization_params, sway_locale: current_sway_locale).to_builder(with_positions: false).attributes!,
           status: :ok
  end

  def update
    o = Organization.find_by(id: params[:id])
    if o
      o.update!(organization_params)
      render json: o.to_builder(with_positions: false).attributes!, status: :ok
    else
      render json: { success: false, message: 'Organization not found.' }, status: :ok
    end
  end

  private

  def organization_params
    params.require(:organization).permit(:name, :icon_path, :sway_locale_id)
  end
end
