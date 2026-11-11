# frozen_string_literal: true

# @lat: [[domain-entities#People and identity]]
class UserBillSharesController < ApplicationController
  skip_before_action :authenticate_sway_user!, only: :show

  def create
    bill_id = params[:bill_id]
    bill = Bill.find_by(id: bill_id) if bill_id.is_a?(String) || bill_id.is_a?(Integer)
    if bill.nil?
      if mobile_api_request?
        render_error(code: "not_found", message: "Bill not found.", status: :not_found)
      else
        redirect_to bills_path, alert: "Bill not found."
      end
      return
    end

    share = find_or_create_share(bill)
    respond_with_share(share, bill)
  end

  def show
    share_uuid = params[:share_uuid]
    share = UserBillShare.find_by(share_uuid:) if share_uuid.is_a?(String) && share_uuid.present?
    if share.nil? || share.bill.nil?
      redirect_to bills_path, alert: "Bill not found."
      return
    end

    share.redeem!(opener: current_user)
    redirect_to bill_path(share.bill_id)
  end

  private

  def find_or_create_share(bill)
    current_user.user_bill_shares.find_or_create_by!(bill:)
  rescue ActiveRecord::RecordNotUnique
    current_user.user_bill_shares.find_by!(bill:)
  end

  def respond_with_share(share, bill)
    if mobile_api_request?
      render json: UserBillShareResource.new(share).serializable_hash, status: :ok
    else
      flash[:bill_share_path] = share.share_path
      target = url_from(request.referer) || bill_path(bill)
      redirect_to target
    end
  end
end
