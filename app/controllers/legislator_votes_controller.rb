# frozen_string_literal: true

class LegislatorVotesController < ApplicationController
  # @lat: [[legislator-votes-controller-admin-entry#index serializes through LegislatorResource]]
  include LegislatorVoteUpserter

  before_action :verify_is_sway_admin, only: %i[create]
  before_action :set_bill, only: %i[show create]

  def index
    # @lat: [[legislator-votes-controller-admin-entry#index serializes through LegislatorResource]]
    legislators = current_user&.legislators(current_sway_locale) || []
    if legislators.any?
      ActiveRecord::Associations::Preloader.new(
        records: legislators,
        associations: [
          {photo_attachment: :blob},
          {legislator_terms: [:seat, {district: :sway_locale}, :legislator_district_scores, :legislator_locale_scores]}
        ]
      ).call
    end
    render json: LegislatorResource.new(legislators).serializable_hash,
      status: :ok
  end

  def show
    # @lat: [[legislator-votes-controller-admin-entry#index serializes through LegislatorResource]]
    render json: LegislatorVote.where(bill: @bill).map(&:to_sway_json),
      status: :ok
  end

  def create
    votes = legislator_votes_params[:legislator_votes]
    # @lat: [[legislator-votes-controller-admin-entry#create's guard against a nil vote list]]
    return error_redirect("No votes submitted.") if votes.blank?

    failed_legislator_ids = [] #: Array[Integer]
    skipped_legislator_ids = [] #: Array[Integer]
    ActiveRecord::Base.transaction do
      votes.each do |param|
        legislator_id = param[:legislator_id].to_i
        SwayLogging.info(
          "LegislatorVotesController.create - upserting LegislatorVote for Bill: #{@bill.id}, Legislator: #{legislator_id}"
        )
        vote = Struct.new(:support).new(param[:support])
        # @lat: [[legislator-votes-controller-admin-entry#Collecting failures instead of committing partial rows]]
        upserted = upsert_legislator_vote(legislator_id, vote, source: "manual")
        if upserted == :skipped
          skipped_legislator_ids << legislator_id
        elsif upserted != true
          failed_legislator_ids << legislator_id
        end
      end

      raise ActiveRecord::Rollback if failed_legislator_ids.any?
    end

    if failed_legislator_ids.any?
      error_redirect("Failed to save votes for legislator(s): #{failed_legislator_ids.join(", ")}.")
    else
      # @lat: [[bill-creator-redirect-query-params#notice: rides the flash instead]]
      redirect_to creator_bill_creator_path(
        id: @bill.id,
        event_key: "organizations"
      ),
        **saved_flash(votes.size, skipped_legislator_ids)
    end
  rescue => e
    SwayLogging.log_exception(
      "legislator_votes.create_failed",
      exception: e,
      bill_id: @bill&.id,
      sway_locale_id: @bill&.sway_locale_id,
      vote_count: legislator_votes_params[:legislator_votes]&.size
    )
    # @lat: [[legislator-votes-controller-admin-entry#index serializes through LegislatorResource]]
    error_redirect(e.message)
  end

  private

  def error_redirect(message)
    redirect_to creator_bill_creator_path(id: @bill&.id, event_key: "legislator_votes"),
      inertia: {errors: {legislator_votes: message}}
  end

  # @lat: [[legislator-votes-controller-admin-entry#Collecting failures instead of committing partial rows]]
  def saved_flash(vote_count, skipped_legislator_ids)
    return {notice: "Legislator Votes Saved"} if skipped_legislator_ids.empty?

    found = Legislator.where(id: skipped_legislator_ids).index_by(&:id)
    names = skipped_legislator_ids.map { |id| found[id]&.full_name || "legislator ##{id}" }
    {
      notice: "Saved #{vote_count - skipped_legislator_ids.size} of #{vote_count} legislator votes.",
      alert: "No term covers this bill's date for #{names.to_sentence}. Fix the term and save again."
    }
  end

  def set_bill
    @bill =
      Bill.includes(:legislator_votes, :sway_locale).find_by(
        id: legislator_votes_params[:bill_id]
      )
  end

  def legislator_votes_params
    params.permit(:bill_id, legislator_votes: %i[legislator_id support])
  end
end
