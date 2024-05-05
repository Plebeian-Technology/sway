# typed: true
class UserVotesController < ApplicationController
  before_action :redirect_if_no_current_user

  def index
    render json: UserVote.where(user: current_user), status: :ok
  end

  def show
    render json: UserVote.find_by!(
      user: current_user,
      bill_id: params[:id],
    ).to_json, status: :ok
  end

  # POST /user_votes or /user_votes.json
  def create
    render json: UserVote.find_or_create_by!(
      user: current_user,
      bill_id: user_vote_params[:bill_id],
      support: user_vote_params[:support],
    ).to_json, status: :ok
  end

  private

    # Only allow a list of trusted parameters through.
    def user_vote_params
      params.require(:user_vote).permit(:bill_id, :support)
    end
end
