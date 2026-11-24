# frozen_string_literal: true

class OrganizationsController < ApplicationController
  # @lat: [[organizations-controller#Rename changes the shared locale record]]
  include BillCreatorTabRedirects

  before_action :verify_is_sway_admin, only: %i[create update]
  before_action :set_organization, only: %i[show update]
  before_action :set_bill, only: %i[create]

  def index
    render json:
             Organization.where(sway_locale_id: current_sway_locale&.id)
               # @lat: [[public-organizations-endpoint#Why the list preloads icons and the detail does not]]
               .with_attached_icon
               .includes(organization_bill_positions: :bill)
               .map(&:to_sway_json),
      status: :ok
  end

  def show
    organization = @organization
    if organization
      render json: organization.to_sway_json, status: :ok
    else
      # @lat: [[organizations-controller#A missing organization returns a real 404]]
      render_error(code: "not_found", message: "Organization not found.", status: :not_found)
    end
  end

  def create
    errored = false
    # @lat: [[organizations-controller#Create errors retain their row and field shape]]
    errors = {
      organizations:
        organizations_params[:organizations].map do |_|
          {label: nil, value: nil, summary: nil, support: nil, icon_url: nil}
        end
    }

    ActiveRecord::Base.transaction do
      organizations_params[:organizations].each_with_index do |param, index|
        organization = find_or_initialize_organization_from_param(param)

        organization.icon.attach(param[:icon_signed_id]) if param[:icon_signed_id].present?
        # @lat: [[organizations-controller#Icon addresses keep their source meaning]]
        submitted_icon_url = param[:icon_signed_id].present? ? nil : param[:icon_url]
        organization.icon_url = our_own_asset_url?(submitted_icon_url) ? nil : submitted_icon_url

        if organization.save
          position =
            OrganizationBillPosition.find_or_initialize_by(
              organization:,
              bill: @bill
            )
          position.support = OrganizationBillPosition.normalize_support(param[:support]) || param[:support]
          # @lat: [[organization-position-removal#A Neutral position carries no testimony]]
          position.summary =
            if OrganizationBillPosition.neutral_support?(position.support)
              OrganizationBillPosition::DEFAULT_SUMMARY
            else
              param[:summary]
            end
          position.source_kind = OrganizationBillPosition::SourceKind::SWAY_ADMIN
          position.source_url = nil
          # @lat: [[organization-position-removal#A saved position is a published one]]
          position.active = true

          unless position.save
            errored = true
            # @lat: [[organizations-controller#Create errors retain their row and field shape]]
            position.errors.objects.each do |error|
              next unless errors[:organizations][index].key?(error.attribute)
              errors[:organizations][index][error.attribute] =
                "#{error.attribute.to_s.capitalize} #{error.message}"
            end
          end
        else
          errored = true
          organization.errors.objects.each do |error|
            attribute_by_key = {name: :label, id: :value, icon_url: :icon_url}
            attr = attribute_by_key[error.attribute]
            next unless attr.present? && errors[:organizations][index].key?(attr)
            errors[:organizations][index][attr] = "#{attr} #{error.message.capitalize}"
          end
        end
      end

      # @lat: [[organizations-controller#A failed batch rolls back every row write]]
      raise ActiveRecord::Rollback if errored
    end

    if errored
      flash[:alert] = "Error Saving Supporting/Opposing Arguments"
      redirect_to bill_creator_tab_path(
        bill_creator_tab_param,
        bill_id: @bill.id,
        default: :positions_bill_creator_path,
        event_key: "organizations"
      ),
        inertia: {
          errors: errors
        }
    else
      flash[:notice] = "Supporting/Opposing Arguments Saved"
      redirect_to bill_creator_tab_path(
        bill_creator_tab_param,
        bill_id: @bill.id,
        default: :positions_bill_creator_path,
        saved: "Supporting/Opposing Arguments Saved",
        event_key: "organizations"
      )
    end
  end

  # @lat: [[organizations-controller#Rename changes the shared locale record]]
  def update
    back_path =
      if params[:bill_id].present?
        bill_creator_tab_path(
          bill_creator_tab_param,
          bill_id: params[:bill_id],
          default: :positions_bill_creator_path,
          event_key: "organizations"
        )
      else
        new_bill_creator_path(bill_creator_tab: "positions")
      end

    organization = @organization
    if organization.nil?
      flash[:alert] = "Organization not found."
      return redirect_to back_path
    end

    if organization.update(organization_update_params)
      flash[:notice] = "Organization renamed to #{organization.name}."
    else
      flash[:alert] = "Could not rename organization: #{organization.errors.full_messages.join(", ")}"
    end
    redirect_to back_path
  end

  private

  def set_bill
    @bill =
      Bill.includes(:organization_bill_positions, :sway_locale).find(
        organizations_params[:bill_id]
      )
  end

  # @lat: [[organizations-controller#A missing organization returns a real 404]]
  def set_organization
    @organization =
      Organization.includes(organization_bill_positions: :bill).find_by(
        id: params[:id]
      )
  end

  def organizations_params
    params.permit(
      :bill_id,
      organizations: %i[label value summary support icon_url icon_signed_id]
    )
  end

  # @lat: [[organizations-controller#Rename changes the shared locale record]]
  def organization_update_params
    params.permit(:name)
  end

  # @lat: [[organizations-controller#Icon addresses keep their source meaning]]
  def our_own_asset_url?(url)
    return true if url.blank?

    URI.parse(url.to_s).path.to_s.start_with?("/rails/active_storage/")
  rescue URI::InvalidURIError
    false
  end

  # @lat: [[organizations-controller#Organization lookup stays within the bill's locale]]
  def find_or_initialize_organization_from_param(param)
    if param[:value].present?
      existing = Organization.where(sway_locale_id: @bill.sway_locale_id).find_by(id: param[:value])
      return existing if existing
    end

    normalized_name = param[:label].to_s.squeeze(" ").strip
    Organization
      .where(sway_locale_id: @bill.sway_locale_id)
      .where("LOWER(name) = ?", normalized_name.downcase)
      .first ||
      Organization.new(
        name: normalized_name,
        sway_locale: @bill.sway_locale
      )
  end
end
