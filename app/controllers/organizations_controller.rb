# frozen_string_literal: true
# typed: true

class OrganizationsController < ApplicationController
  include SwayGoogleCloudStorage

  before_action :verify_is_admin, only: %i[create]
  before_action :set_organization, only: %i[show]
  before_action :set_bill, only: %i[create]

  def index
    render json: Organization.where(sway_locale_id: current_sway_locale&.id).map(&:to_sway_json), status: :ok
  end

  def show
    if @organization.present?
      render json: @organization.to_sway_json, status: :ok
    else
      render json: {success: false, message: "Organization not found."}, status: :ok
    end
  end

  def create
    errored = T.let(false, T::Boolean)
    errors = {
      organization: organizations_params[:organizations].map do |_|
        {
          label: nil,
          value: nil,
          summary: nil,
          support: nil,
          icon_path: nil
        }
      end
    }

    organizations_params[:organizations].each_with_index do |param, index|
      organization = find_or_initialize_organization_from_param(param)
      current_icon_path = organization.icon_path.freeze
      organization.icon_path = param[:icon_path]

      if organization.save
        organization.remove_icon(current_icon_path)

        position = OrganizationBillPosition.find_or_initialize_by(organization:, bill: @bill)
        position.support = param[:support]
        position.summary = param[:summary]

        unless position.save
          errored = true
          position.errors.each do |e|
            if errors[:organizations][index].key?(e.attribute)
              errors[:organizations][index][e.attribute] = "#{e.attribute.capitalize} #{e.message}"
            end
          end
        end
      else
        errored = true
        organization.errors.each do |e|
          attribute_by_key = {
            name: :label,
            id: :value,
            icon_path: :icon_path
          }

          attr = attribute_by_key[e.attribute]
          if attr.present? && errors[:organizations][index].key?(attr)
            errors[:organizations][index][attr] = "#{attr} #{e.message.capitalize}"
          end
        end
      end
    end

    if errored
      redirect_to edit_bill_path(@bill.id, {event_key: "organizations"}), inertia: {errors: errors}
    else
      redirect_to edit_bill_path(@bill.id, {saved: "Supporting/Opposing Arguments Saved", event_key: "organizations"})
    end
  end

  private

  def set_bill
    @bill = Bill.includes(:organization_bill_positions, :sway_locale).find(organizations_params[:bill_id])
  end

  def organizations_params
    params.permit(:bill_id, organizations: %i[label value summary support icon_path])
  end

  def find_or_initialize_organization_from_param(param)
    o = param[:value].blank? ? nil : Organization.find_by(id: param[:value]).presence
    o || Organization.find_or_initialize_by(name: param[:label], sway_locale: @bill.sway_locale)
  end
end
