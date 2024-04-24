# typed: true
class UserDistrictsController < ApplicationController
  before_action :set_user_district, only: %i[ show edit update destroy ]

  # GET /user_districts or /user_districts.json
  def index
    @user_districts = UserDistrict.all
  end

  # GET /user_districts/1 or /user_districts/1.json
  def show
  end

  # GET /user_districts/new
  def new
    @user_district = UserDistrict.new
  end

  # GET /user_districts/1/edit
  def edit
  end

  # POST /user_districts or /user_districts.json
  def create
    @user_district = UserDistrict.new(user_district_params)

    respond_to do |format|
      if @user_district.save
        format.html { redirect_to user_district_url(@user_district), notice: "User district was successfully created." }
        format.json { render :show, status: :created, location: @user_district }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user_district.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /user_districts/1 or /user_districts/1.json
  def update
    respond_to do |format|
      if @user_district.update(user_district_params)
        format.html { redirect_to user_district_url(@user_district), notice: "User district was successfully updated." }
        format.json { render :show, status: :ok, location: @user_district }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user_district.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_districts/1 or /user_districts/1.json
  def destroy
    @user_district.destroy!

    respond_to do |format|
      format.html { redirect_to user_districts_url, notice: "User district was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user_district
      @user_district = UserDistrict.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_district_params
      params.require(:user_district).permit(:district_id, :user_id)
    end
end
