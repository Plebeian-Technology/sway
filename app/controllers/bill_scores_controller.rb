class BillScoresController < ApplicationController
  before_action :set_bill_score, only: %i[ show edit update destroy ]

  # GET /bill_scores or /bill_scores.json
  def index
    @bill_scores = BillScore.all
  end

  # GET /bill_scores/1 or /bill_scores/1.json
  def show
  end

  # GET /bill_scores/new
  def new
    @bill_score = BillScore.new
  end

  # GET /bill_scores/1/edit
  def edit
  end

  # POST /bill_scores or /bill_scores.json
  def create
    @bill_score = BillScore.new(bill_score_params)

    respond_to do |format|
      if @bill_score.save
        format.html { redirect_to bill_score_url(@bill_score), notice: "Bill score was successfully created." }
        format.json { render :show, status: :created, location: @bill_score }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @bill_score.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /bill_scores/1 or /bill_scores/1.json
  def update
    respond_to do |format|
      if @bill_score.update(bill_score_params)
        format.html { redirect_to bill_score_url(@bill_score), notice: "Bill score was successfully updated." }
        format.json { render :show, status: :ok, location: @bill_score }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @bill_score.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /bill_scores/1 or /bill_scores/1.json
  def destroy
    @bill_score.destroy!

    respond_to do |format|
      format.html { redirect_to bill_scores_url, notice: "Bill score was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_bill_score
      @bill_score = BillScore.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def bill_score_params
      params.require(:bill_score).permit(:bill_id)
    end
end
