# frozen_string_literal: true

# @lat: [[admin-locales-registration-visibility#Why one user can count toward three locale rows]]
# @lat: [[mobile-admin-area#The locales screen]]
module Admin
  class LocalesController < ApplicationController
    before_action :verify_is_sway_admin

    def show
      render_inertia_or_json(page: Pages::ADMIN_LOCALES, props: AdminLocaleSummary.new.as_props)
    end

    # @lat: [[identity-and-access#The stand-in account borrows a jurisdiction's sample address]]
    def update
      sway_locale = SwayLocale.find(params[:id])

      if sample_address_present?
        sway_locale.update!(sample_address_params)
        respond_after_write(admin_locales_path, notice: "Sample address saved.", json: updated_locale_json(sway_locale))
      else
        respond_after_write(admin_locales_path, json: updated_locale_json(sway_locale))
      end
    rescue ActiveRecord::RecordInvalid => e
      respond_after_write(admin_locales_path, alert: e.message, errors: e.record.errors)
    end

    private

    def updated_locale_json(sway_locale)
      return {} unless mobile_api_request?

      {sway_locale: AdminLocaleSampleAddressResource.new(sway_locale).serializable_hash}
    end

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
