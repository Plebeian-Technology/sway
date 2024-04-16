class UserLegislatorsController < ApplicationController
  before_action :set_user_legislator, only: %i[ show edit update destroy ]

  # GET /user_legislators or /user_legislators.json
  def index
    @user_legislators = UserLegislator.all
  end

  # GET /user_legislators/1 or /user_legislators/1.json
  def show
  end

  # GET /user_legislators/new
  def new
    @user_legislator = UserLegislator.new
  end

  # GET /user_legislators/1/edit
  def edit
  end

  # POST /user_legislators or /user_legislators.json
  def create
    @user_legislator = UserLegislator.new(user_legislator_params)

    respond_to do |format|
      if @user_legislator.save
        format.html { redirect_to user_legislator_url(@user_legislator), notice: "User legislator was successfully created." }
        format.json { render :show, status: :created, location: @user_legislator }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user_legislator.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /user_legislators/1 or /user_legislators/1.json
  def update
    respond_to do |format|
      if @user_legislator.update(user_legislator_params)
        format.html { redirect_to user_legislator_url(@user_legislator), notice: "User legislator was successfully updated." }
        format.json { render :show, status: :ok, location: @user_legislator }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user_legislator.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_legislators/1 or /user_legislators/1.json
  def destroy
    @user_legislator.destroy!

    respond_to do |format|
      format.html { redirect_to user_legislators_url, notice: "User legislator was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user_legislator
      @user_legislator = UserLegislator.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_legislator_params
      params.require(:user_legislator).permit(:legislator_id, :user_id)
    end
end
