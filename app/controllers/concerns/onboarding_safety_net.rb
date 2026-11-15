# frozen_string_literal: true

# @lat: [[onboarding-safety-net#Why every onboarding endpoint answers an unexpected error]]
module OnboardingSafetyNet
  extend ActiveSupport::Concern

  ONBOARDING_UNAVAILABLE_MESSAGE = "Something went wrong on our side. Please try again."

  included do
    around_action :rescue_unexpected_onboarding_error, prepend: true
  end

  private

  # @lat: [[onboarding-safety-net#Why every onboarding endpoint answers an unexpected error#Errors Rails already answers pass through]]
  def rescue_unexpected_onboarding_error
    yield
  rescue => e
    raise unless ActionDispatch::ExceptionWrapper.status_code_for_exception(e.class.name) == 500

    SwayLogging.log_exception(
      "onboarding.unexpected_error",
      exception: e,
      controller: controller_path,
      action: action_name
    )
    Sentry.capture_exception(e, extra: {controller: controller_path, action: action_name})
    render_onboarding_unavailable
  end

  def render_onboarding_unavailable
    if mobile_api_request? || is_a?(Api::V1::BaseController)
      render_error(code: "onboarding_unavailable", message: ONBOARDING_UNAVAILABLE_MESSAGE, status: :service_unavailable)
    else
      redirect_back_or_to(root_path, alert: ONBOARDING_UNAVAILABLE_MESSAGE)
    end
  end
end
