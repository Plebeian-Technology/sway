# typed: true

class BillsController < ApplicationController
  before_action :redirect_if_no_current_user
  before_action :verify_is_admin, only: %i[new edit create update destroy]
  before_action :set_bill, only: %i[show edit update destroy]

  # GET /bills or /bills.json
  def index
    render inertia: 'Bills', props: {
      bills: Bill.where(sway_locale: current_sway_locale).map do |b|
               b.to_builder.attributes!
             end
    }
  end

  # GET /bills/1 or /bills/1.json
  def show
    b = T.let(Bill.find(params[:id]), T.nilable(Bill))
    if b.present?
      render inertia: 'Bill', props: {
        bill: b.to_builder.attributes!
      }
    else
      redirect_to bills_path
    end
  end

  # GET /bills/new
  def new
    @bill = Bill.new
  end

  # GET /bills/1/edit
  def edit
  end

  # POST /bills or /bills.json
  def create
    @bill = Bill.new(bill_params)

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
    params.require(:bill).permit(:external_id, :external_version, :title, :link, :chamber, :house_vote_date_time_utc,
                                 :senate_vote_date_time_utc, :chamber, :introduced_date_time_utc, :category, :sponsor_id, :level)
  end
end
