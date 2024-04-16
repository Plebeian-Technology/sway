class LegislatorsController < ApplicationController
  before_action :set_legislator, only: %i[ show edit update destroy ]

  # GET /legislators or /legislators.json
  def index
    @legislators = Legislator.all
  end

  # GET /legislators/1 or /legislators/1.json
  def show
  end

  # GET /legislators/new
  def new
    @legislator = Legislator.new
  end

  # GET /legislators/1/edit
  def edit
  end

  # POST /legislators or /legislators.json
  def create
    @legislator = Legislator.new(legislator_params)

    respond_to do |format|
      if @legislator.save
        format.html { redirect_to legislator_url(@legislator), notice: "Legislator was successfully created." }
        format.json { render :show, status: :created, location: @legislator }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @legislator.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /legislators/1 or /legislators/1.json
  def update
    respond_to do |format|
      if @legislator.update(legislator_params)
        format.html { redirect_to legislator_url(@legislator), notice: "Legislator was successfully updated." }
        format.json { render :show, status: :ok, location: @legislator }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @legislator.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /legislators/1 or /legislators/1.json
  def destroy
    @legislator.destroy!

    respond_to do |format|
      format.html { redirect_to legislators_url, notice: "Legislator was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_legislator
      @legislator = Legislator.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def legislator_params
      params.require(:legislator).permit(:external_id, :active, :link, :email, :district, :title, :first_name, :last_name, :phone, :fax, :address_id, :party, :photo_url)
    end
end
