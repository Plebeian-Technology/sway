# typed: true
class SwayLocalesController < ApplicationController
  before_action :set_sway_locale, only: %i[ show edit update destroy ]

  # GET /sway_locales or /sway_locales.json
  def index
    @sway_locales = SwayLocale.all
  end

  # GET /sway_locales/1 or /sway_locales/1.json
  def show
  end

  # GET /sway_locales/new
  def new
    @sway_locale = SwayLocale.new
  end

  # GET /sway_locales/1/edit
  def edit
  end

  # POST /sway_locales or /sway_locales.json
  def create
    @sway_locale = SwayLocale.new(sway_locale_params)

    respond_to do |format|
      if @sway_locale.save
        format.html { redirect_to sway_locale_url(@sway_locale), notice: "Sway locale was successfully created." }
        format.json { render :show, status: :created, location: @sway_locale }
      else
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: @sway_locale.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /sway_locales/1 or /sway_locales/1.json
  def update
    respond_to do |format|
      if @sway_locale.update(sway_locale_params)
        format.html { redirect_to sway_locale_url(@sway_locale), notice: "Sway locale was successfully updated." }
        format.json { render :show, status: :ok, location: @sway_locale }
      else
        format.html { render :edit, status: :unprocessable_entity }
        format.json { render json: @sway_locale.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /sway_locales/1 or /sway_locales/1.json
  def destroy
    @sway_locale.destroy!

    respond_to do |format|
      format.html { redirect_to sway_locales_url, notice: "Sway locale was successfully destroyed." }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_sway_locale
      @sway_locale = SwayLocale.find(params[:id])
    end

    # Only allow a list of trusted parameters through.
    def sway_locale_params
      params.require(:sway_locale).permit(:city, :state, :country)
    end
end
