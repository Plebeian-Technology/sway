# frozen_string_literal: true

# typed: true

class UserVotesController < ApplicationController
  def index
    render json: UserVote.where(user: current_user), status: :ok
  end

  def show
    uv = UserVote.find_by(
      user: current_user,
      bill_id: params[:id]
    )
    if uv.present?
      render json: uv.to_json, status: :ok
    else
      render json: {}, status: :no_content
    end
  end

  # POST /user_votes or /user_votes.json
  def create
    uv = UserVote.find_or_initialize_by(
      user: current_user,
      bill_id: user_vote_params[:bill_id]
    )
    uv.support = user_vote_params[:support]
    uv.save

    redirect_to user_vote_params[:redirect_to], inertia: {
      errors: uv.errors
    }
  end

  private

  # Only allow a list of trusted parameters through.
  def user_vote_params
    params.permit(:bill_id, :support, :redirect_to)
  end
end
