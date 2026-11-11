# frozen_string_literal: true

# @lat: [[public-marketing-and-meta-pages#Why MarketingController.mobile_download renders plain ERB, not Inertia]]
# @lat: [[public-marketing-and-meta-pages#Why MarketingController sms, privacy and terms exist]]
class MarketingController < ApplicationController
  skip_before_action :authenticate_sway_user!
  skip_before_action :is_api_request_and_is_route_api_accessible?

  # @lat: [[public-marketing-and-meta-pages#Why /sms, /privacy and /terms are Inertia pages under a second, minimal entrypoint]]
  layout "public"

  def mobile_download
    # @lat: [[public-marketing-and-meta-pages#Why the Apple App Store id is a placeholder]]
    @apple_app_store_id = Sway::Settings.mobile.apple_app_store_id
    @android_package = "vote.sway.app"
    # @lat: [[public-marketing-and-meta-pages#Why MarketingController.mobile_download renders plain ERB, not Inertia]]
    render template: "pages/mobile_download", layout: "application"
  end

  # @lat: [[public-marketing-and-meta-pages#Why MarketingController sms, privacy and terms exist]]
  def sms
    render inertia: Pages::SMS, props: {sms_phone: Sway::TwilioClient.display_from_phone}
  end

  # @lat: [[public-marketing-and-meta-pages#Why MarketingController sms, privacy and terms exist]]
  def privacy
    render inertia: Pages::PRIVACY
  end

  # @lat: [[public-marketing-and-meta-pages#Why MarketingController sms, privacy and terms exist]]
  def terms
    render inertia: Pages::TERMS
  end
end
