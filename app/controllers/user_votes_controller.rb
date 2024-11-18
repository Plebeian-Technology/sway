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
    # render json: UserVote.find_or_create_by!(
    #   user: current_user,
    #   bill_id: user_vote_params[:bill_id],
    #   support: user_vote_params[:support]
    # ).to_json, status: :ok
    UserVote.find_or_create_by!(
      user: current_user,
      bill_id: user_vote_params[:bill_id],
      support: user_vote_params[:support]
    )
    redirect_to "/bills/#{user_vote_params[:bill_id]}"
  end

  private

  # Only allow a list of trusted parameters through.
  def user_vote_params
    params.require(:user_vote).permit(:bill_id, :support)
  end
end
