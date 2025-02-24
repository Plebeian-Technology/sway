# frozen_string_literal: true
# typed: true

module Buckets
  class AssetsController < ApplicationController
    extend T::Sig
    include SwayGoogleCloudStorage

    before_action :verify_is_admin, only: %i[create]

    # Upload a file to the assets bucket in GCP
    # return the new file location
    def create
      render json: {
        bucket_file_path: file_name,
        url: generate_put_signed_url_v4(bucket_name: SwayGoogleCloudStorage::BUCKETS[:ASSETS], file_name:,
          content_type: buckets_assets_params[:mime_type])
      }, status: :ok
    end

    private

    def file_name
      "#{T.cast(current_sway_locale, SwayLocale).name}/#{buckets_assets_params[:name]}"
    end

    # https://stackoverflow.com/a/16804560/6410635
    def file_suffix
      Rack::Mime::MIME_TYPES.invert[buckets_assets_params[:mime_type]]
    end

    # :name will typically be the name of the organization uploading an icon
    # :mime_type is the type of file being uploaded, i.e. image/png
    def buckets_assets_params
      params.require(:asset).permit(:name, :mime_type)
    end
  end
end
