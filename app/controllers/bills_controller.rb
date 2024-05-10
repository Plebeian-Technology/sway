# typed: true

class BillsController < ApplicationController
  include SwayGoogleCloudStorage

  before_action :verify_is_admin, only: %i[new edit create update destroy]
  before_action :set_bill, only: %i[show edit update destroy]

  # GET /bills or /bills.json
  def index
    T.unsafe(self).render_bills(lambda do
      {
        bills: current_sway_locale&.bills || []
      }
    end)
  end

  # GET /bills/1 or /bills/1.json
  def show
    if @bill.present?
      T.unsafe(self).render_bill(lambda do
        {
          bill: @bill.to_builder.attributes!,
          positions: @bill.organization_bill_positions.map { |obp| obp.to_builder.attributes! },
          legislatorVotes: @bill.legislator_votes.map { |lv| lv.to_builder.attributes! },
          sponsor: @bill.legislator.to_builder.attributes!,
          userVote: UserVote.find_by(
            user: current_user,
            bill_id: @bill.id
          )&.attributes
        }
      end)
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
                                         positions: []
                                       })
  end

  # GET /bills/1/edit
  def edit
    return unless @bill.present?

    T.unsafe(self).render_bill_creator({
                                         bills: (current_sway_locale&.bills || []).map { |b| b.to_builder.attributes! },
                                         bill: @bill.to_builder.attributes!,
                                         legislators: (current_sway_locale&.legislators || []).map do |l|
                                                        l.to_builder.attributes!
                                                      end,
                                         legislatorVotes: @bill.legislator_votes.map { |lv| lv.to_builder.attributes! },
                                         positions: @bill.organization_bill_positions.map do |obp|
                                                      obp.to_builder.attributes!
                                                    end
                                       })
  end

  # POST /bills or /bills.json
  def create
    render json: Bill.find_or_create_by!(
      **bill_params,
      sway_locale: current_sway_locale
    ).to_builder.attributes!, status: :ok
  end

  # PATCH/PUT /bills/1 or /bills/1.json
  def update
    render json: { success: false, message: @bill.errors.join(', ') }, status: :ok unless @bill.present?

    current_audio_path = @bill.audio_bucket_path.freeze
    if @bill.update(bill_params)
      remove_audio(current_audio_path)

      render json: @bill.to_builder.attributes!, status: :ok
    else
      render json: { success: false, message: @bill.errors.join(', ') }, status: :ok
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
    delete_file(
      bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS],
      file_name: audio_path
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
