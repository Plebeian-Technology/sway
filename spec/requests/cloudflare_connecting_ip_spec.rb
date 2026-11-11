# frozen_string_literal: true

require "rails_helper"

# @lat: [[cloudflare-trusted-proxies#Why CloudflareConnectingIpMiddleware normalizes X-Forwarded-For before RemoteIp]]
RSpec.describe "CloudflareConnectingIpMiddleware client IP normalization", type: :request do
  default_proxies = ActionDispatch::RemoteIp::TRUSTED_PROXIES
  cloudflare_warp_proxy = IPAddr.new("1.1.1.0/24")

  build_stack = ->(trusted_proxies = default_proxies) do
    inner = ->(env) do
      req = ActionDispatch::Request.new(env)
      [200, {"content-type" => "text/plain"}, [req.remote_ip.to_s]]
    end
    remote_ip = ActionDispatch::RemoteIp.new(inner, true, trusted_proxies)
    CloudflareConnectingIpMiddleware.new(remote_ip)
  end

  it "inserts CloudflareConnectingIpMiddleware before ActionDispatch::RemoteIp in the application stack" do
    middlewares = Rails.application.middleware.map(&:klass)
    cf_index = middlewares.index(CloudflareConnectingIpMiddleware)
    remote_ip_index = middlewares.index(ActionDispatch::RemoteIp)

    expect(cf_index).not_to be_nil
    expect(remote_ip_index).not_to be_nil
    expect(cf_index).to be < remote_ip_index
  end

  it "resolves request.remote_ip to CF-Connecting-IP even when CF-Connecting-IP is a trusted Cloudflare WARP IP and X-Forwarded-For or Forwarded is spoofed" do
    stack = build_stack.call(default_proxies + [cloudflare_warp_proxy])
    env = Rack::MockRequest.env_for("/up").merge(
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_CF_CONNECTING_IP" => "1.1.1.1",
      "HTTP_X_FORWARDED_FOR" => "198.51.100.77, 1.1.1.1",
      "HTTP_FORWARDED" => "for=198.51.100.77",
      "HTTP_CLIENT_IP" => "198.51.100.77"
    )

    _status, _headers, body = stack.call(env)

    expect(body.join).to eq("1.1.1.1")
    expect(env["HTTP_FORWARDED"]).to be_nil
    expect(env["HTTP_X_FORWARDED_FOR"]).to eq("1.1.1.1")
  end

  it "preserves standard X-Forwarded-For resolution when HTTP_CF_CONNECTING_IP is absent while stripping spoofed HTTP_FORWARDED" do
    stack = build_stack.call
    env = Rack::MockRequest.env_for("/up").merge(
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.42",
      "HTTP_FORWARDED" => "for=198.51.100.99"
    )

    _status, _headers, body = stack.call(env)

    expect(body.join).to eq("203.0.113.42")
    expect(env["HTTP_FORWARDED"]).to be_nil
  end

  it "ignores malformed HTTP_CF_CONNECTING_IP values and preserves existing X-Forwarded-For" do
    stack = build_stack.call
    env = Rack::MockRequest.env_for("/up").merge(
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_CF_CONNECTING_IP" => "not-an-ip",
      "HTTP_X_FORWARDED_FOR" => "203.0.113.42"
    )

    _status, _headers, body = stack.call(env)

    expect(body.join).to eq("203.0.113.42")
  end
end
