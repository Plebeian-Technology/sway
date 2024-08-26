# frozen_string_literal: true
# typed: true

class OrganizationsController < ApplicationController
  include SwayGoogleCloudStorage

  before_action :verify_is_admin, only: %i[create update]
  before_action :set_organization, only: %i[show update]

  def index
    render json: Organization.where(sway_locale_id: current_sway_locale&.id).map { |o|
                   o.to_builder(with_positions: false).attributes!
                 }, status: :ok
  end

  def show
    if @organization.present?
      render json: @organization.to_builder(with_positions: true).attributes!, status: :ok
    else
      render json: {success: false, message: "Organization not found."}, status: :ok
    end
  end

  def create
    render json: Organization.find_or_create_by!(**organization_params, sway_locale: current_sway_locale).to_builder(with_positions: false).attributes!,
      status: :ok
  end

  def update
    if @organization.present?
      current_icon_path = @organization.icon_path.freeze
      @organization.update!(organization_params)
      remove_icon(current_icon_path)

      render json: @organization.to_builder(with_positions: false).attributes!, status: :ok
    else
      render json: {success: false, message: "Organization not found."}, status: :ok
    end
  end

  private

  def set_organization
    @organization = Organization.find_by(id: params[:id])
  end

  def organization_params
    params.require(:organization).permit(:name, :icon_path, :sway_locale_id)
  end

  def remove_icon(current_icon_path)
    return unless @organization.icon_path != current_icon_path

    delete_file(bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS], file_name: current_icon_path)
  end
end
