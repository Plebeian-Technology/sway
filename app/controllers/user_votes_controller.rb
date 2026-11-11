# frozen_string_literal: true

class UserVotesController < ApplicationController
  # @lat: [[user-votes-controller-notes#Why VOTE_ALREADY_RECORDED_MESSAGE is a shared constant]]
  VOTE_ALREADY_RECORDED_MESSAGE =
    "Your vote on this bill was already recorded and cannot be changed."

  def index
    # @lat: [[serializer-whitelist-endpoints#BillsController follows the same rule]]
    render json: UserVoteResource.new(UserVote.joins(:bill).where(user: current_user)).serializable_hash,
      status: :ok
  end

  def show
    uv = UserVote.joins(:bill).find_by(user: current_user, bill_id: params[:id])
    if uv.present?
      # @lat: [[serializer-whitelist-endpoints#BillsController follows the same rule]]
      render json: UserVoteResource.new(uv).serializable_hash, status: :ok
    else
      # @lat: [[user-votes-controller-notes#Why show answers 204, not 200 with null]]
      head :no_content
    end
  end

  def create
    incoming = user_vote_params[:support].to_s.upcase.strip

    # @lat: [[user-votes-controller-notes#Why create resolves target through url_from before writing]]
    # @type var target: String
    target =
      url_from(user_vote_params[:redirect_to]) ||
      bill_path(user_vote_params[:bill_id])

    bill = Bill.find_by(id: user_vote_params[:bill_id])
    if bill && !bill.active
      if mobile_api_request?
        render json: {
                 error: {
                   code: "bill_inactive",
                   message: "Voting is closed for this bill."
                 }
               },
          status: :unprocessable_content
      else
        flash[:alert] = "Voting is closed for this bill."
        redirect_to bill_path(bill.id), inertia: {errors: {base: "Voting is closed for this bill."}}
      end
      return
    end

    # @lat: [[user-votes-controller-notes#Why a cast vote can never be changed]]
    existing = UserVote.joins(:bill).find_by(user: current_user, bill_id: user_vote_params[:bill_id])
    if existing
      return already_voted_response(existing, incoming, target)
    end

    uv = UserVote.new(
      user: current_user,
      bill_id: user_vote_params[:bill_id],
      support: incoming
    )
    saved = uv.save
    if saved
      ArticleEngagementTrackerService.track_vote(
        bill: uv.bill,
        stance: incoming,
        attribution_key: current_attribution_key
      )
    end

    if !saved && mobile_api_request?
      render json: {
               error: {
                 code: "validation_failed",
                 message: "Vote could not be saved",
                 details: uv.errors.as_json
               }
             },
        status: :unprocessable_content
    elsif mobile_api_request?
      redirect_or_json(target, flash_message: "Vote saved!")
    else
      flash[:notice] = "Vote saved!" if saved
      unless saved
        flash[
          :alert
        ] = "There was an error saving your vote. Please try again."
      end

      redirect_to(target, inertia: {errors: uv.errors})
    end
  rescue ActiveRecord::RecordNotUnique
    # @lat: [[user-votes-controller-notes#Why create rescues RecordNotUnique]]
    winner = UserVote.joins(:bill).find_by(user: current_user, bill_id: user_vote_params[:bill_id])
    if winner
      already_voted_response(winner, incoming, target)
    else
      raise
    end
  end

  private

  # @lat: [[user-votes-controller-notes#Why a cast vote can never be changed]]
  def already_voted_response(existing, incoming, target)
    if existing.support == incoming
      if mobile_api_request?
        redirect_or_json(target, flash_message: "Vote saved!")
      else
        flash[:notice] = "Vote saved!"
        redirect_to(target)
      end
    elsif mobile_api_request?
      render json: {
               error: {
                 code: "vote_already_recorded",
                 message: VOTE_ALREADY_RECORDED_MESSAGE
               }
             },
        status: :unprocessable_content
    else
      flash[:alert] = VOTE_ALREADY_RECORDED_MESSAGE
      redirect_to(target, inertia: {errors: {vote: VOTE_ALREADY_RECORDED_MESSAGE}})
    end
  end

  def user_vote_params
    params.permit(:bill_id, :support, :redirect_to)
  end
end
