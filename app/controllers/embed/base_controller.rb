# frozen_string_literal: true

# @lat: [[embeddable-bill-widget#Embeddable bill widget#Controller implementation]]
module Embed
  class BaseController < ActionController::Base
    protect_from_forgery with: :null_session

    rescue_from ActiveRecord::RecordNotFound, with: :render_not_found

    prepend_before_action :prevent_session_cookies
    before_action :reject_js_request_format
    after_action :prevent_session_cookies
    after_action :configure_embed_headers

    content_security_policy do |policy|
      policy.frame_ancestors "*"
    end
    content_security_policy_report_only false

    layout "embed"

    private

    def render_not_found
      head :not_found
    end

    def prevent_session_cookies
      request.session_options[:skip] = true
      response.headers.delete("Set-Cookie")
    end

    def configure_embed_headers
      response.headers["Cache-Control"] = "public, max-age=60, s-maxage=300, stale-while-revalidate=600"
      response.headers.delete("X-Frame-Options")
    end

    # @lat: [[bad-request-responses#Bad request responses#JavaScript format probes answer 406]]
    def reject_js_request_format
      head :not_acceptable if request.format.js?
    end
  end
end
