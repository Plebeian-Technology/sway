class LegislatorVotesController < ApplicationController
  before_action :set_legislator_vote, only: %i[ show edit update destroy ]

  # GET /legislator_votes or /legislator_votes.json
  def index
    @legislator_votes = LegislatorVote.all
  end

  # GET /legislator_votes/1 or /legislator_votes/1.json
  def show
  end

  # GET /legislator_votes/new
  def new
    @legislator_vote = LegislatorVote.new
  end

  # GET /legislator_votes/1/edit
  def edit
  end

  # POST /legislator_votes or /legislator_votes.json
  def create
    @legislator_vote = LegislatorVote.new(legislator_vote_params)

    respond_to do |format|
      if @legislator_vote.save
        format.html { redirect_to legislator_vote_url(@legislator_vote), notice: "Legislator vote was successfully created." }
        format.json { render :show, status: :created, location: @legislator_vote }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @legislator_vote.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /legislator_votes/1 or /legislator_votes/1.json
  def update
    respond_to do |format|
      if @legislator_vote.update(legislator_vote_params)
        format.html { redirect_to legislator_vote_url(@legislator_vote), notice: "Legislator vote was successfully updated." }
        format.json { render :show, status: :ok, location: @legislator_vote }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @legislator_vote.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /legislator_votes/1 or /legislator_votes/1.json
  def destroy
    @legislator_vote.destroy!

    respond_to do |format|
      format.html { redirect_to legislator_votes_url, notice: "Legislator vote was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_legislator_vote
      @legislator_vote = LegislatorVote.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def legislator_vote_params
      params.require(:legislator_vote).permit(:legislator_id, :bill_id, :support)
    end
end
