# frozen_string_literal: true

module Buckets
  class AssetsController < ApplicationController
    include SwayGoogleCloudStorage

    before_action :verify_is_sway_admin

    def create
      safe_name = sanitized_asset_name
      if safe_name.nil?
        return render_error(
          code: "invalid_filename",
          message: "Asset filename is required.",
          status: :unprocessable_content
        )
      end

      bucket_path = file_name(safe_name)
      render json: {
               bucket_file_path: bucket_path,
               url:
                 generate_put_signed_url_v4(
                   bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS],
                   file_name: bucket_path,
                   content_type: buckets_assets_params[:mime_type]
                 )
             },
        status: :ok
    end

    private

    def sanitized_asset_name
      raw = buckets_assets_params[:name].to_s.strip
      return nil if raw.blank?

      base = File.basename(raw)
      return nil if base.blank? || base == "." || base == ".." || base == "/"

      base
    end

    def file_name(safe_name = sanitized_asset_name)
      "#{current_sway_locale.name}/#{safe_name}"
    end

    def buckets_assets_params
      params.require(:asset).permit(:name, :mime_type)
    end
  end
end
