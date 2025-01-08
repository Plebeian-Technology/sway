# frozen_string_literal: true
# typed: true

class LegislatorVotesController < ApplicationController
  before_action :verify_is_admin, only: %i[create]
  before_action :set_bill, only: %i[show create]

  def index
    render json: current_user&.legislators(T.cast(current_sway_locale, SwayLocale)), status: :ok
  end

  def show
    render json: LegislatorVote.where(bill: @bill).map { |lv| lv.to_builder.attributes! }, status: :ok
  end

  def create
    LegislatorVote.where(bill: @bill).destroy_all

    begin
      legislator_votes_params[:legislator_votes].each do |param|
        LegislatorVote.create!({
          bill_id: @bill.id,
          legislator_id: param[:legislator_id].to_i,
          support: param[:support]
        })
      end
    rescue Exception => e # rubocop:disable Lint/RescueException
      Rails.logger.error(e)
      redirect_to edit_bill_path(@bill.id, {event_key: "legislator_votes"}), inertia: {
        errors: {legislator_votes: e}
      }
    else
      redirect_to edit_bill_path(@bill.id, {saved: "Legislator Votes Saved", event_key: "organizations"})
    end
  end

  private

  def set_bill
    @bill = Bill.includes(:legislator_votes, :sway_locale).find_by(id: legislator_votes_params[:bill_id])
  end

  def legislator_votes_params
    params.permit(:bill_id, legislator_votes: %i[legislator_id support])
  end
end
