# frozen_string_literal: true

# @lat: [[registration-funnel-telemetry#Attribution preservation]]
module Shortener
  class ShortenedUrlsController < ActionController::Metal
    include ActionController::StrongParameters
    include ActionController::Redirecting
    include ActionController::Instrumentation
    include ActionController::Cookies
    include Rails.application.routes.url_helpers
    include Shortener

    def show
      token = ::Shortener::ShortenedUrl.extract_token(params[:id])
      track = Shortener.ignore_robots.blank? || request.human?
      url = ::Shortener::ShortenedUrl.fetch_with_token(token: token, additional_params: params, track: track)

      if url && url[:shortened_url].present? && params[:id].present?
        cookies.permanent[:sway_attribution_key] = "s:#{params[:id]}"
      end

      if url
        redirect_to url[:url], status: :moved_permanently
      else
        redirect_to root_path
      end
    end
  end
end
