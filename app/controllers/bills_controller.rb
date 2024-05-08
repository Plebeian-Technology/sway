# typed: true

class BillsController < ApplicationController

  before_action :verify_is_admin, only: %i[new edit create update destroy]
  before_action :set_bill, only: %i[show edit update destroy]

  # GET /bills or /bills.json
  def index
    T.unsafe(self).render_bills(lambda do
      {
        bills: Bill.where(sway_locale: current_sway_locale).map do |b|
          b.to_builder.attributes!
        end
      }
    end)
  end

  # GET /bills/1 or /bills/1.json
  def show
    b = T.let(Bill.find(params[:id]), T.nilable(Bill))
    if b.present?
      T.unsafe(self).render_bill(lambda do
        {
          bill: b.to_builder.attributes!,
          organizations: b.organization_bill_positions.map{ |obp| obp.to_builder.attributes! },
          legislator_votes: b.legislator_votes.map{ |lv| lv.to_builder.attributes! },
          user_vote: UserVote.find_by(
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
  end

  # GET /bills/1/edit
  def edit
    b = T.let(Bill.find(params[:id]), T.nilable(Bill))
    if b.present?
      T.unsafe(self).render_bill(lambda do
        {
          bill: b.to_builder.attributes!,
          organizations: b.organization_bill_positions.map{ |obp| obp.to_builder.attributes! },
          legislator_votes: b.legislator_votes.map{ |lv| lv.to_builder.attributes! },
          user_vote: UserVote.find_by(
            user: current_user,
            bill_id: params[:id]
          )&.attributes
        }
      end)
    end
  end

  # POST /bills or /bills.json
  def create
    @bill = Bill.new(bill_params)
    @bill.legislator_id

    respond_to do |format|
      if @bill.save
        format.html { redirect_to bill_url(@bill), notice: 'Bill was successfully created.' }
        format.json { render :show, status: :created, location: @bill }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @bill.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /bills/1 or /bills/1.json
  def update
    respond_to do |format|
      if @bill.update(bill_params)
        format.html { redirect_to bill_url(@bill), notice: 'Bill was successfully updated.' }
        format.json { render :show, status: :ok, location: @bill }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @bill.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /bills/1 or /bills/1.json
  def destroy
    @bill.destroy!

    respond_to do |format|
      format.html { redirect_to bills_url, notice: 'Bill was successfully destroyed.' }
      format.json { head :no_content }
    end
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
      :legislator_id,
      :sway_locale_id
    )
  end
end
