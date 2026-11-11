# frozen_string_literal: true

# @lat: [[bill-creator-positions-tab#Why testimony admin write controllers omit an else branch on service outcomes]]
class TestimonyCoverageAcknowledgementsController < ApplicationController
  before_action :verify_is_sway_admin
  before_action :set_bill

  # @lat: [[bill-creator-positions-tab#The acknowledgement returns to the only tab that offers it]]
  def create
    target = positions_bill_creator_path(@bill)

    case AcknowledgeTestimonyCoverageService.new(
      bill: @bill, actor: current_user, digest: params[:digest]
    ).call
    when :run_in_flight
      redirect_to target,
        inertia: {errors: {testimony_coverage: "A clean-testimony run is in progress on this bill — wait for " \
          "it to finish, then acknowledge the new numbers."}}
    when :nothing_left_out
      redirect_to target,
        inertia: {errors: {testimony_coverage: "There is nothing to acknowledge — every letter reached the model."}}
    when :digest_mismatch
      redirect_to target,
        inertia: {errors: {testimony_coverage: "The testimony coverage numbers changed since this page loaded " \
          "— reload and try again."}}
    when :acknowledged
      flash[:notice] = "Acknowledged the missing testimony on #{@bill.external_id}."
      redirect_to target
    end
  end

  private

  def set_bill
    @bill = Bill.find(params[:bill_id])
  end
end
