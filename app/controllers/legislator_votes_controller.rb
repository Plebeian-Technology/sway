# frozen_string_literal: true
# typed: true

class LegislatorVotesController < ApplicationController
  before_action :verify_is_admin, only: %i[create]
  before_action :set_bill, only: %i[show create]

  def index
    render json: current_user&.legislators(T.cast(current_sway_locale, SwayLocale)), status: :ok
  end

  def show
    render json: LegislatorVote.where(bill: @bill).map(&:to_sway_json), status: :ok
  end

  def create
    legislator_votes_params[:legislator_votes].each do |param|
      Rails.logger.info("LegislatorVotesController.create - creating new LegislatorVote for Bill: #{@bill.id}, Legislator: #{param[:legislator_id]}")
      legislator = Legislator.find(param[:legislator_id].to_i)

      existing_legislator_vote = LegislatorVote.find_by(legislator:, bill: @bill.id)
      existing_support = existing_legislator_vote&.support.freeze

      new_legislator_vote = LegislatorVote.new({
        bill_id: @bill.id,
        legislator:,
        support: param[:support]
      })

      if existing_legislator_vote.nil?
        new_legislator_vote.save!
        Rails.logger.info("LegislatorVotesController.create - NEW Vote for Legislator #{legislator.id} TO: #{new_legislator_vote.support}")
      elsif existing_legislator_vote.support != new_legislator_vote.support
        existing_legislator_vote.update!(support: new_legislator_vote.support)
        Rails.logger.info("LegislatorVotesController.create - Vote: #{existing_legislator_vote.id} for Legislator #{legislator.id} CHANGED to: #{new_legislator_vote.support} from: #{existing_support}")
      else
        # Legislator Vote is unchanged, LegislatorDistrict score should remain unchanged
        Rails.logger.info("LegislatorVotesController.create - Vote for Legislator #{legislator.id} is UNCHANGED")
        next
      end
    end
  rescue Exception => e # rubocop:disable Lint/RescueException
    Rails.logger.error(e)
    redirect_to edit_bill_path(@bill.id, {event_key: "legislator_votes"}), inertia: {
      errors: {legislator_votes: e}
    }
  else
    redirect_to(edit_bill_path(@bill.id), {saved: "Legislator Votes Saved", event_key: "organizations"})
  end

  private

  def set_bill
    @bill = Bill.includes(:legislator_votes, :sway_locale).find_by(id: legislator_votes_params[:bill_id])
  end

  def legislator_votes_params
    params.permit(:bill_id, legislator_votes: %i[legislator_id support])
  end
end
