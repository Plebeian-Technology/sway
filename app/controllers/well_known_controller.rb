# Related Origin Request for Webauthn
# https://web.dev/articles/webauthn-related-origin-requests

class WellKnownController < ApplicationController
  skip_before_action :authenticate_user!

  def index
    Rails.logger.info("WellKnownController.index.request.host - #{request.host}")
    if request.host == "app.sway.vote"
      render json: {
        origins: [
          "https://sway.vote"
        ]
      }
    end
  end
end
