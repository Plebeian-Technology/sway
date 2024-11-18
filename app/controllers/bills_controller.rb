# frozen_string_literal: true
# typed: true

class BillsController < ApplicationController
  include SwayGoogleCloudStorage

  before_action :verify_is_admin, only: %i[new edit create update destroy]
  before_action :set_bill, only: %i[show edit update destroy]

  # GET /bills or /bills.json
  def index
    T.unsafe(self).render_bills(lambda do
      {
        bills: current_sway_locale&.bills&.map { |b| b.to_builder.attributes! } || [],
        user_votes: current_user.user_votes # Loading by SwayLocale would cause N+1 queries. UserVote belongs to Bill
      }
    end)
  end

  # GET /bills/1 or /bills/1.json
  def show
    if @bill.present?
      T.unsafe(self).render_bill(-> { @bill.render(current_user) })
    else
      redirect_to bills_path
    end
  end

  # ADMIN ONLY ROUTES

  # GET /bills/new
  def new
    T.unsafe(self).render_bill_creator({
      bills: (current_sway_locale&.bills || []).map { |b| b.to_builder.attributes! },
      bill: Bill.new.attributes,
      legislators: (current_sway_locale&.legislators || []).map do |l|
                     l.to_builder.attributes!
                   end,
      legislatorVotes: [],
      positions: [],
      tabKey: params[:tabKey]
    })
  end

  # GET /bills/1/edit
  def edit
    return if @bill.blank?

    T.unsafe(self).render_bill_creator({
      bills: (current_sway_locale&.bills || []).map { |b| b.to_builder.attributes! },
      bill: @bill.to_builder.attributes!,
      legislators: (current_sway_locale&.legislators || []).map do |l|
                     l.to_builder.attributes!
                   end,
      legislatorVotes: @bill.legislator_votes.map { |lv| lv.to_builder.attributes! },
      positions: @bill.organization_bill_positions.map do |obp|
                   obp.to_builder.attributes!
                 end,
      tabKey: params[:tabKey]
    })
  end

  # POST /bills or /bills.json
  def create
    b = Bill.find_or_create_by!(
      **bill_params,
      sway_locale: current_sway_locale
    )

    create_vote(b)

    render json: b.to_builder.attributes!, status: :ok
  end

  # PATCH/PUT /bills/1 or /bills/1.json
  def update
    render json: {success: false, message: @bill.errors.join(", ")}, status: :ok if @bill.blank?

    current_audio_path = @bill.audio_bucket_path.freeze
    if @bill.update(bill_params)
      remove_audio(current_audio_path)

      create_vote(@bill)

      render json: @bill.to_builder.attributes!, status: :ok
    else
      render json: {success: false, message: @bill.errors.join(", ")}, status: :ok
    end
  end

  # DELETE /bills/1 or /bills/1.json
  def destroy
    @bill.destroy!

    new
  end

  private

  # Use callbacks to share common setup or constraints between actions.
  def set_bill
    @bill = Bill.includes(:legislator_votes, :organization_bill_positions, :legislator, :sway_locale).find(params[:id])
  end

  def remove_audio(audio_path)
    return unless @bill.audio_bucket_path != audio_path

    delete_file(
      bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS],
      file_name: audio_path
    )
  end

  def create_vote(b)
    return unless vote_params[:house_roll_call_vote_number] || vote_params[:senate_roll_call_vote_number]

    Vote.find_or_create_by!(bill_id: b.id,
      house_roll_call_vote_number: vote_params[:house_roll_call_vote_number],
      senate_roll_call_vote_number: vote_params[:senate_roll_call_vote_number])
  end

  def vote_params
    params.permit(
      :house_roll_call_vote_number,
      :senate_roll_call_vote_number
    )
  end

  # Only allow a list of trusted parameters through.
  def bill_params
    params.require(:bill).permit(
      :external_id,
      :external_version,
      :title,
      :link,
      :chamber,
      :introduced_date_time_utc,
      :house_vote_date_time_utc,
      :senate_vote_date_time_utc,
      :chamber,
      :category,
      :level,
      :summary,
      :status,
      :active,
      :audio_bucket_path,
      :audio_by_line,
      :legislator_id,
      :sway_locale_id
    )
  end
end
