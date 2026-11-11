#!/usr/bin/env ruby
# frozen_string_literal: true

# @lat: [[local-store-uploads#Why the App Store Connect client mints its own token]]
# Usage: asc.rb apps | asc.rb get <path>

require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

HOST = "api.appstoreconnect.apple.com"
KEY_DIRS = ["./private_keys", "#{Dir.home}/private_keys", "#{Dir.home}/.private_keys",
  "#{Dir.home}/.appstoreconnect/private_keys"].freeze

def die(message)
  warn "asc.rb: #{message}"
  exit 1
end

def key_id
  ENV["APP_STORE_CONNECT_API_KEY_ID"] || die("APP_STORE_CONNECT_API_KEY_ID is unset")
end

def issuer_id
  ENV["APP_STORE_CONNECT_ISSUER_ID"] || die("APP_STORE_CONNECT_ISSUER_ID is unset")
end

def key_path
  found = KEY_DIRS.map { |dir| File.join(dir, "AuthKey_#{key_id}.p8") }.find { |path| File.size?(path) }
  found || die("no AuthKey_#{key_id}.p8 in #{KEY_DIRS.join(", ")}")
end

def bearer_token
  now = Time.now.to_i
  header = {alg: "ES256", kid: key_id, typ: "JWT"}
  claims = {iss: issuer_id, iat: now, exp: now + 1200, aud: "appstoreconnect-v1"}
  signing_input = [header, claims].map { |part| Base64.urlsafe_encode64(JSON.dump(part), padding: false) }.join(".")

  key = OpenSSL::PKey::EC.new(File.read(key_path))
  der = key.sign(OpenSSL::Digest.new("SHA256"), signing_input)
  r, s = OpenSSL::ASN1.decode(der).value.map { |v| v.value.to_s(2).rjust(32, "\x00") }
  "#{signing_input}.#{Base64.urlsafe_encode64(r + s, padding: false)}"
end

def get(path)
  uri = URI("https://#{HOST}#{path}")
  req = Net::HTTP::Get.new(uri)
  req["Authorization"] = "Bearer #{bearer_token}"
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.request(req) }
  die("GET #{path} returned #{response.code}\n#{response.body}") unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body)
end

case ARGV[0]
when "apps"
  rows = Array(get("/v1/apps?limit=200&fields[apps]=name,bundleId,sku")["data"])
  die("this key authenticates but can see no apps at all") if rows.empty?
  rows.each do |app|
    attributes = app["attributes"] || {}
    puts format("%-12s %-28s %s", app["id"], attributes["bundleId"], attributes["name"])
  end
when "app-id"
  bundle_id = ARGV[1] || die("usage: asc.rb app-id <bundle id>")
  row = Array(get("/v1/apps?limit=200&fields[apps]=bundleId")["data"])
    .find { |app| app.dig("attributes", "bundleId") == bundle_id }
  die("this key reaches no app with bundle id #{bundle_id}") if row.nil?
  puts row["id"]
when "get"
  puts JSON.pretty_generate(get(ARGV[1] || die("usage: asc.rb get <path>")))
else
  die("usage: asc.rb apps | asc.rb get <path>")
end
