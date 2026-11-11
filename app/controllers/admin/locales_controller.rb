# frozen_string_literal: true

# @lat: [[admin-locales-registration-visibility#Why one user can count toward three locale rows]]
module Admin
  class LocalesController < ApplicationController
    before_action :verify_is_sway_admin

    def show
      render inertia: Pages::ADMIN_LOCALES, props: AdminLocaleSummary.new.as_props
    end

    # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
    def update
      sway_locale = SwayLocale.find(params[:id])

      if sample_address_present?
        sway_locale.update!(sample_address_params)
        redirect_to admin_locales_path, notice: "Sample address saved."
      else
        redirect_to admin_locales_path
      end
    end

    private

    def sample_address_present?
      return false unless params[:sway_locale].is_a?(ActionController::Parameters)

      %i[sample_street sample_postal_code sample_latitude sample_longitude].any? do |key|
        params[:sway_locale].key?(key)
      end
    end

    def sample_address_params
      params
        .require(:sway_locale)
        .permit(:sample_street, :sample_postal_code, :sample_latitude, :sample_longitude)
        .to_h
        .transform_values(&:presence)
    end
  end
end
