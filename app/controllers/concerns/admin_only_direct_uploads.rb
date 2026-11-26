# frozen_string_literal: true

# @lat: [[admin-only-direct-uploads-design#Why the request spec checks blob count, not just status]]
module AdminOnlyDirectUploads
  extend ActiveSupport::Concern

  included do
    include JsonErrorRenderable
    include ApiKeyAuthenticatable

    # @lat: [[admin-only-direct-uploads-design#Why a bearer token decides identity on its own]]
    skip_forgery_protection if: :sway_admin_bearer_token?
    before_action :require_sway_admin_for_upload
  end

  private

  # @lat: [[admin-only-direct-uploads-design#Why both the allow and refuse branches are logged]]
  def require_sway_admin_for_upload
    user = request.authorization.present? ? upload_user_from_bearer_token : upload_user_from_session

    if user&.is_sway_admin?
      SwayLogging.info(
        "direct_upload.allowed",
        user_id: user.id,
        filename: params.dig(:blob, :filename),
        byte_size: params.dig(:blob, :byte_size),
        content_type: params.dig(:blob, :content_type),
        remote_ip: request.remote_ip
      )
      return
    end

    # @lat: [[cloudflare-trusted-proxies#Why spec/requests/force_ssl_spec.rb checks config files and deleted methods, not live HTTPS behavior]]
    SwayLogging.warn(
      "direct_upload.refused",
      user_id: user&.id,
      filename: params.dig(:blob, :filename),
      remote_ip: request.remote_ip
    )

    render_error(code: "forbidden", message: "Admin access required.", status: :forbidden)
  end

  def sway_admin_bearer_token?
    return false if request.authorization.blank?

    upload_user_from_bearer_token&.is_sway_admin? || false
  end

  def upload_user_from_bearer_token
    bearer = authenticate_with_api_key
    bearer if bearer.is_a?(User)
  end

  def upload_user_from_session
    user = User.find_by(id: session[:user_id])
    if user && !BrowserSession.current?(session, user)
      BrowserSession.forget(session)
      user = nil
    end
    user
  end
end
