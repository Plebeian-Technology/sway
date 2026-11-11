# frozen_string_literal: true

# @lat: [[mobile-api-client-contract#Why the server error shape has a code field]]
# @lat: [[render-error-nonnil-fields-workaround#Why JsonErrorRenderable doesn't scrub details itself]]
module JsonErrorRenderable
  extend ActiveSupport::Concern

  private

  def render_error(code:, message:, status:, details: nil)
    payload = {error: {code: code, message: message}} #: Hash[Symbol, Hash[Symbol, untyped]]
    payload[:error][:details] = details if details
    render json: payload, status: status
  end
end
