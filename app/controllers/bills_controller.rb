# typed: true

class BillsController < ApplicationController
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
    b = T.let(Bill.includes(:legislator_votes, :organization_bill_positions, :legislator).find(params[:id]),
              T.nilable(Bill))
    if b.present?
      T.unsafe(self).render_bill(lambda do
        {
          bill: b.to_builder.attributes!,
          positions: b.organization_bill_positions.map { |obp| obp.to_builder.attributes! },
          legislatorVotes: b.legislator_votes.map { |lv| lv.to_builder.attributes! },
          sponsor: b.legislator.to_builder.attributes!,
          userVote: UserVote.find_by(
            user: current_user,
            bill_id: params[:id]
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
    b = T.let(Bill.includes(:legislator_votes, :organization_bill_positions).find(params[:id]), T.nilable(Bill))
    return unless b.present?

    T.unsafe(self).render_bill_creator({
      bills: (current_sway_locale&.bills || []).map { |b| b.to_builder.attributes! },
      bill: b.to_builder.attributes!,
      legislators: (current_sway_locale&.legislators || []).map do |l|
                    l.to_builder.attributes!
                  end,
      legislatorVotes: b.legislator_votes.map { |lv| lv.to_builder.attributes! },
      positions: b.organization_bill_positions.map do |obp|
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
    if @bill.update(bill_params)
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
    @bill = Bill.find(params[:id])
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
      :legislator_id,
      :sway_locale_id
    )
  end
end
