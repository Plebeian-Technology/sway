# frozen_string_literal: true
# typed: true

class BillOrganizationsController < ApplicationController
  include SwayGoogleCloudStorage

  before_action :verify_is_admin, only: %i[create]
  before_action :set_organization, only: %i[show]
  before_action :set_bill, only: %i[create]

  def index
    render json: BillOrganization.where(sway_locale_id: current_sway_locale&.id).map(&:to_sway_json), status: :ok
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
      bill_organization: bill_organizations_params[:bill_organization].map do |_|
        {
          label: nil,
          value: nil,
          summary: nil,
          support: nil,
          icon_path: nil
        }
      end
    }

    bill_organizations_params[:bill_organization].each_with_index do |param, index|
      bill_organization = find_or_initialize_organization_from_param(param)
      current_icon_path = bill_organization.icon_path.freeze
      bill_organization.icon_path = param[:icon_path]

      if bill_organization.save
        bill_organization.remove_icon(current_icon_path)

        position = OrganizationBillPosition.find_or_initialize_by(bill_organization:, bill: @bill)
        position.support = param[:support]
        position.summary = param[:summary]

        unless position.save
          errored = true
          position.errors.each do |e|
            if errors[:bill_organization][index].key?(e.attribute)
              errors[:bill_organization][index][e.attribute] = "#{e.attribute.capitalize} #{e.message}"
            end
          end
        end
      else
        errored = true
        bill_organization.errors.each do |e|
          attribute_by_key = {
            name: :label,
            id: :value,
            icon_path: :icon_path
          }

          attr = attribute_by_key[e.attribute]
          if attr.present? && errors[:bill_organization][index].key?(attr)
            errors[:bill_organization][index][attr] = "#{attr} #{e.message.capitalize}"
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
    @bill = Bill.includes(:organization_bill_positions, :sway_locale).find(bill_organizations_params[:bill_id])
  end

  def bill_organizations_params
    params.permit(:bill_id, bill_organization: %i[label value summary support icon_path])
  end

  def find_or_initialize_organization_from_param(param)
    o = param[:value].blank? ? nil : BillOrganization.find_by(id: param[:value]).presence
    o || BillOrganization.find_or_initialize_by(name: param[:label], sway_locale: @bill.sway_locale)
  end
end
