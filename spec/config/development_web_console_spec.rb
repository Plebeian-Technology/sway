# frozen_string_literal: true

require "rails_helper"

RSpec.describe "config/environments/development.rb web_console.permissions" do
  before do
    @development_rb_path = Rails.root.join("config", "environments", "development.rb").to_s
    @fake_config = ActiveSupport::OrderedOptions.new
    %i[
      web_console
      action_controller
      public_file_server
      active_storage
      action_mailer
      x
      active_support
      active_record
      active_job
      assets
      action_view
      solid_queue
    ].each do |section|
      @fake_config[section] = ActiveSupport::OrderedOptions.new
    end
    @fake_config[:active_record][:encryption] = ActiveSupport::OrderedOptions.new
    @fake_config[:hosts] = []
    @fake_config[:root] = Rails.root

    allow(Rails.application).to receive(:config).and_return(@fake_config)
    allow(Resolv).to receive(:getaddress).with("host.docker.internal").and_return("192.168.65.254")
  end

  it "uses a /32 mask for host.docker.internal and allows 127.0.0.1/8 when DEV_TUNNEL_HOST is unset" do
    with_env("IS_DOCKER" => "1", "DEV_TUNNEL_HOST" => nil) do
      load @development_rb_path
    end

    expect(@fake_config[:web_console][:permissions]).to eq(["192.168.65.254/32", "127.0.0.1/8"])
  end

  it "preserves local and /32 Docker host gateway permissions when DEV_TUNNEL_HOST is localhost" do
    with_env("IS_DOCKER" => "1", "DEV_TUNNEL_HOST" => "localhost") do
      load @development_rb_path
    end

    expect(@fake_config[:web_console][:permissions]).to eq(["192.168.65.254/32", "127.0.0.1/8"])
  end

  it "sets web_console.permissions to an empty array when DEV_TUNNEL_HOST is a non-localhost tunnel host" do
    with_env("IS_DOCKER" => "1", "DEV_TUNNEL_HOST" => "dev.example.test") do
      load @development_rb_path
    end

    expect(@fake_config[:web_console][:permissions]).to eq([])
  end
end
