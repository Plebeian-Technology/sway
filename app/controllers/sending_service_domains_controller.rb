# frozen_string_literal: true

# @lat: [[bill-creator-positions-tab#Why testimony admin write controllers omit an else branch on service outcomes]]
class SendingServiceDomainsController < ApplicationController
  before_action :verify_is_sway_admin
  before_action :set_domain

  def update
    case SetSendingServiceDomainLabelService.new(
      domain: @domain, actor: current_user, label: params[:label]
    ).call
    when :invalid_label
      redirect_to redirect_target,
        inertia: {errors: {sending_service: "Unknown label value (expected confirmed|none)"}}
    when :confirmed
      flash[:notice] = "Confirmed #{@domain.domain} as a sending service."
      redirect_to redirect_target
    when :removed
      flash[:notice] = "Removed the sending-service label from #{@domain.domain}."
      redirect_to redirect_target
    end
  end

  private

  def set_domain
    @domain = SendingServiceDomain.find(params[:id])
  end

  def redirect_target
    bill_id = Integer(params[:bill_id], exception: false)
    return admin_root_path if bill_id.nil?

    pipeline_bill_creator_path(id: bill_id)
  end
end
