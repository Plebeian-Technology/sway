# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  # @lat: [[outbound-email#Why mailers default to outreach@sway.vote and bake invite expiry into signed tokens]]
  default from: "outreach@sway.vote"
  layout "mailer"
end
