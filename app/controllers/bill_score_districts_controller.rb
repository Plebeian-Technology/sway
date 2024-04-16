class BillScoreDistrictsController < ApplicationController
  before_action :set_bill_score_district, only: %i[ show edit update destroy ]

  # GET /bill_score_districts or /bill_score_districts.json
  def index
    @bill_score_districts = BillScoreDistrict.all
  end

  # GET /bill_score_districts/1 or /bill_score_districts/1.json
  def show
  end

  # GET /bill_score_districts/new
  def new
    @bill_score_district = BillScoreDistrict.new
  end

  # GET /bill_score_districts/1/edit
  def edit
  end

  # POST /bill_score_districts or /bill_score_districts.json
  def create
    @bill_score_district = BillScoreDistrict.new(bill_score_district_params)

    respond_to do |format|
      if @bill_score_district.save
        format.html { redirect_to bill_score_district_url(@bill_score_district), notice: "Bill score district was successfully created." }
        format.json { render :show, status: :created, location: @bill_score_district }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @bill_score_district.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /bill_score_districts/1 or /bill_score_districts/1.json
  def update
    respond_to do |format|
      if @bill_score_district.update(bill_score_district_params)
        format.html { redirect_to bill_score_district_url(@bill_score_district), notice: "Bill score district was successfully updated." }
        format.json { render :show, status: :ok, location: @bill_score_district }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @bill_score_district.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /bill_score_districts/1 or /bill_score_districts/1.json
  def destroy
    @bill_score_district.destroy!

    respond_to do |format|
      format.html { redirect_to bill_score_districts_url, notice: "Bill score district was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_bill_score_district
      @bill_score_district = BillScoreDistrict.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def bill_score_district_params
      params.require(:bill_score_district).permit(:bill_score_id, :district, :for, :against)
    end
end
