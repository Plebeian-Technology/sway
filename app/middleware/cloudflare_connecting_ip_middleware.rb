# frozen_string_literal: true

require "ipaddr"

# @lat: [[cloudflare-trusted-proxies#Why CloudflareConnectingIpMiddleware normalizes X-Forwarded-For before RemoteIp]]
class CloudflareConnectingIpMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    env.delete("HTTP_FORWARDED")

    cf_ip = valid_ip(env["HTTP_CF_CONNECTING_IP"])
    if cf_ip
      env["HTTP_X_FORWARDED_FOR"] = cf_ip
      env.delete("HTTP_CLIENT_IP")
    end

    @app.call(env)
  end

  private

  def valid_ip(raw_ip)
    candidate = raw_ip.to_s.strip
    return nil if candidate.empty? || candidate.include?("/")

    IPAddr.new(candidate)
    candidate
  rescue IPAddr::InvalidAddressError, IPAddr::AddressFamilyError
    nil
  end
end
