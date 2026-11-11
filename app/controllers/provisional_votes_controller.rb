# frozen_string_literal: true

class ProvisionalVotesController < ApplicationController
  # @lat: [[low-friction-voting#Provisional vote capture and cookie lifecycle]]

  skip_before_action :authenticate_sway_user!

  rescue_from ActiveRecord::RecordNotFound do
    render json: {ok: false, error: "Bill not found"}, status: :not_found
  end

  def create
    bill = Bill.find(params[:bill_id])

    unless bill.active
      render json: {ok: false, error: "Bill is not active"}, status: :unprocessable_content
      return
    end

    support = params[:support].to_s.upcase.strip
    unless LegislatorVote::Support::FOR_AGAINST.include?(support)
      render json: {ok: false, error: "Invalid support value"}, status: :unprocessable_content
      return
    end

    cookies.encrypted[:sway_pending_vote] = {
      value: {
        bill_id: bill.id,
        support: support,
        nonce: SecureRandom.hex(16),
        created_at: Time.current.iso8601
      },
      expires: 24.hours,
      httponly: true,
      same_site: :lax
    }

    render json: {ok: true, pending_vote: {bill_id: bill.id, support: support}}, status: :ok
  end

  def destroy
    cookies.delete(:sway_pending_vote)
    render json: {ok: true}, status: :ok
  end
end
