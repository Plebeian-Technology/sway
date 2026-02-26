# Related Origin Request for Webauthn
# https://web.dev/articles/webauthn-related-origin-requests

class WellKnownController < ApplicationController
  skip_before_action :authenticate_sway_user!

  def index
    Rails.logger.info(
      "WellKnownController.index.request.host - #{request.host}",
    )
    if request.host == "app.sway.vote"
      return render json: { origins: ["https://sway.vote"] }
    end

    head :no_content
  end
end
