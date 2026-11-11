# frozen_string_literal: true

require "rails_helper"

RSpec.describe "production mail delivery configuration" do
  let(:production) { Rails.root.join("config", "environments", "production.rb").read }
  let(:initializer) { Rails.root.join("config", "initializers", "resend.rb").read }

  # @lat: [[outbound-email#Outbound email#Delivery goes over HTTPS, not SMTP]]
  it "delivers through the resend gem's registered delivery method" do
    expect(production).to match(/config\.action_mailer\.delivery_method = :resend/)
  end

  it "keeps no SMTP relay settings behind" do
    expect(production).not_to match(/smtp_settings/)
    expect(production).not_to match(/sendgrid/i)
  end

  # @lat: [[outbound-email#Outbound email#A trailing newline reads as a revoked key]]
  it "strips the key so a trailing newline cannot read as a revoked credential" do
    expect(initializer).to match(/Resend\.api_key = ENV\["RESEND_EMAIL_API_KEY"\]\.to_s\.strip\.presence/)
  end

  it "declares the key production reads in the deploy env list" do
    deploy = Rails.root.join("config", "deploy.yml").read
    expect(deploy).to include("RESEND_EMAIL_API_KEY")
    expect(deploy).not_to include("SENDGRID_API_KEY")
  end
end
