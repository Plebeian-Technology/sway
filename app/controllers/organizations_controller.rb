# frozen_string_literal: true
# typed: true

class OrganizationsController < ApplicationController
  include SwayGoogleCloudStorage

  before_action :verify_is_admin, only: %i[create]
  before_action :set_organization, only: %i[show]
  before_action :set_bill, only: %i[create]

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
    organizations_params[:organizations].each do |param|
      organization = find_organization_from_param(param)
      current_icon_path = organization.icon_path.freeze
      organization.icon_path = param[:icon_path]

      if organization.save
        organization.remove_icon(current_icon_path)

        position = OrganizationBillPosition.find_or_initialize_by(organization:, bill: @bill)
        position.support = param[:support]
        position.summary = param[:summary]

        begin
          position.save!
        rescue Exception => e # rubocop:disable Lint/RescueException
          Rails.logger.error(e)
          Sentry.capture_exception(e)
        end
      end
    end

    redirect_to edit_bill_path(@bill.id, {saved: "Supporting/Opposing Arguments Saved", event_key: "organizations"})
  end

  private

  def set_bill
    @bill = Bill.includes(:organization_bill_positions, :sway_locale).find(organizations_params[:bill_id])
  end

  def organizations_params
    params.permit(:bill_id, organizations: %i[label value summary support icon_path])
  end

  def find_organization_from_param(param)
    o = param[:value].blank? ? nil : Organization.find_by(id: param[:value]).presence
    o || Organization.find_or_initialize_by(name: param[:label], sway_locale: @bill.sway_locale)
  end
end
