# typed: true
class UserLegislatorScoresController < ApplicationController
  before_action :set_user_legislator_score, only: %i[ show edit update destroy ]

  # GET /user_legislator_scores or /user_legislator_scores.json
  def index
    @user_legislator_scores = UserLegislatorScore.all
  end

  # GET /user_legislator_scores/1 or /user_legislator_scores/1.json
  def show
  end

  # GET /user_legislator_scores/new
  def new
    @user_legislator_score = UserLegislatorScore.new
  end

  # GET /user_legislator_scores/1/edit
  def edit
  end

  # POST /user_legislator_scores or /user_legislator_scores.json
  def create
    @user_legislator_score = UserLegislatorScore.new(user_legislator_score_params)

    respond_to do |format|
      if @user_legislator_score.save
        format.html { redirect_to user_legislator_score_url(@user_legislator_score), notice: "User legislator score was successfully created." }
        format.json { render :show, status: :created, location: @user_legislator_score }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user_legislator_score.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /user_legislator_scores/1 or /user_legislator_scores/1.json
  def update
    respond_to do |format|
      if @user_legislator_score.update(user_legislator_score_params)
        format.html { redirect_to user_legislator_score_url(@user_legislator_score), notice: "User legislator score was successfully updated." }
        format.json { render :show, status: :ok, location: @user_legislator_score }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user_legislator_score.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_legislator_scores/1 or /user_legislator_scores/1.json
  def destroy
    @user_legislator_score.destroy!

    respond_to do |format|
      format.html { redirect_to user_legislator_scores_url, notice: "User legislator score was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user_legislator_score
      @user_legislator_score = UserLegislatorScore.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_legislator_score_params
      params.require(:user_legislator_score).permit(:user_legislator_id, :count_agreed, :count_disagreed, :count_no_legislator_vote, :count_legislator_abstained)
    end
end
