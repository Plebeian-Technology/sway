# frozen_string_literal: true

# @lat: [[admin-only-direct-uploads-design#Why the request spec checks blob count, not just status]]
module AdminOnlyDirectUploads
  extend ActiveSupport::Concern

  included do
    include JsonErrorRenderable

    before_action :require_sway_admin_for_upload
  end

  private

  # @lat: [[admin-only-direct-uploads-design#Why both the allow and refuse branches are logged]]
  def require_sway_admin_for_upload
    user = User.find_by(id: session[:user_id])
    if user && session[:auth_identity].present? && session[:auth_identity].to_i != user.created_at.to_i
      session.delete(:user_id)
      session.delete(:auth_identity)
      user = nil
    end

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
end
