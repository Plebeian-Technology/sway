# typed: true
class UserInvitesController < ApplicationController
  before_action :set_user_invite, only: %i[ show edit update destroy ]

  # GET /user_invites or /user_invites.json
  def index
    @user_invites = UserInvite.all
  end

  # GET /user_invites/1 or /user_invites/1.json
  def show
  end

  # GET /user_invites/new
  def new
    @user_invite = UserInvite.new
  end

  # GET /user_invites/1/edit
  def edit
  end

  # POST /user_invites or /user_invites.json
  def create
    @user_invite = UserInvite.new(user_invite_params)

    respond_to do |format|
      if @user_invite.save
        format.html { redirect_to user_invite_url(@user_invite), notice: "User invite was successfully created." }
        format.json { render :show, status: :created, location: @user_invite }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @user_invite.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /user_invites/1 or /user_invites/1.json
  def update
    respond_to do |format|
      if @user_invite.update(user_invite_params)
        format.html { redirect_to user_invite_url(@user_invite), notice: "User invite was successfully updated." }
        format.json { render :show, status: :ok, location: @user_invite }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @user_invite.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /user_invites/1 or /user_invites/1.json
  def destroy
    @user_invite.destroy!

    respond_to do |format|
      format.html { redirect_to user_invites_url, notice: "User invite was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_user_invite
      @user_invite = UserInvite.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def user_invite_params
      params.require(:user_invite).permit(:user_id, :invitee_email, :invite_expires_on_utc, :invite_accepted_on_utc)
    end
end
