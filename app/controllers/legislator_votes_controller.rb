# typed: true

class LegislatorVotesController < ApplicationController
  before_action :verify_is_admin, only: %i[create update]

  def index
    render json: current_user&.legislators(T.cast(current_sway_locale, SwayLocale)), status: :ok
  end

  def show
    render json: LegislatorVote.where(bill_id: legislator_votes_params[:bill_id]).map { |lv|
                   lv.to_builder.attributes!
                 }, status: :ok
  end

  def create
    LegislatorVote.where(bill_id: legislator_votes_params[:votes].first[:bill_id]).destroy_all

    render json: LegislatorVote.insert_all!(legislator_votes_params[:votes]), status: :ok
  end

  def update
  end

  private

  def legislator_votes_params
    params.require(:legislator_vote).permit(votes: %i[bill_id legislator_id support])
  end

  def legislator_vote_params
    params.require(:legislator_vote).permit(:bill_id, :legislator_id, :support)
  end
end
