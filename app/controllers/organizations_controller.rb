# frozen_string_literal: true

class OrganizationsController < ApplicationController
  before_action :verify_is_sway_admin, only: %i[create]
  before_action :set_organization, only: %i[show]
  before_action :set_bill, only: %i[create]

  def index
    render json:
             Organization.where(sway_locale_id: current_sway_locale&.id).map(
               &:to_sway_json
             ),
           status: :ok
  end

  def show
    if @organization.present?
      render json: @organization.to_sway_json, status: :ok
    else
      render json: {
               success: false,
               message: "Organization not found.",
             },
             status: :ok
    end
  end

  def create
    errored = false
    errors = {
      organization:
        organizations_params[:organizations].map do |_|
          { label: nil, value: nil, summary: nil, support: nil, icon_url: nil }
        end,
    }

    organizations_params[:organizations].each_with_index do |param, index|
      organization = find_or_initialize_organization_from_param(param)

      if param[:icon_signed_id].present?
        organization.icon.attach(param[:icon_signed_id])
        organization.icon_url = icon_url(organization.icon)
      else
        organization.icon_url = param[:icon_url]
      end

      if organization.save
        position =
          OrganizationBillPosition.find_or_initialize_by(
            organization:,
            bill: @bill,
          )
        position.support = param[:support]
        position.summary = param[:summary]

        unless position.save
          errored = true
          position.errors.each do |attribute, message|
            next unless errors[:organizations][index].key?(attribute)
            errors[:organizations][index][
              attribute
            ] = "#{attribute.capitalize} #{message}"
          end
        end
      else
        errored = true
        organization.errors.each do |attribute, message|
          attribute_by_key = { name: :label, id: :value, icon_url: :icon_url }

          attr = attribute_by_key[attribute]
          next unless attr.present? && errors[:organizations][index].key?(attr)
          errors[:organizations][index][attr] = "#{attr} #{message.capitalize}"
        end
      end
    end

    if errored
      flash[:alert] = "Error Saving Supporting/Opposing Arguments"
      redirect_to edit_bill_path(@bill.id, { event_key: "organizations" }),
                  inertia: {
                    errors: errors,
                  }
    else
      flash[:notice] = "Supporting/Opposing Arguments Saved"
      redirect_to edit_bill_path(
                    @bill.id,
                    saved: "Supporting/Opposing Arguments Saved",
                    event_key: "organizations",
                  )
    end
  end

  private

  def set_bill
    @bill =
      Bill.includes(:organization_bill_positions, :sway_locale).find(
        organizations_params[:bill_id],
      )
  end

  def organizations_params
    params.permit(
      :bill_id,
      organizations: %i[label value summary support icon_url icon_signed_id],
    )
  end

  def icon_url(icon)
    Rails.application.routes.url_helpers.rails_storage_proxy_url(
      icon,
      **storage_url_options,
    )
  end

  def storage_url_options
    Rails.application.config.action_mailer.default_url_options ||
      Rails.application.routes.default_url_options ||
      { host: request.host, protocol: request.protocol.delete_suffix(":") }
  end

  def find_or_initialize_organization_from_param(param)
    o =
      (
        if param[:value].blank?
          nil
        else
          Organization.find_by(id: param[:value]).presence
        end
      )
    o ||
      Organization.find_or_initialize_by(
        name: param[:label],
        sway_locale: @bill.sway_locale,
      )
  end
end
