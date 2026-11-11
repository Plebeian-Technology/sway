#!/usr/bin/env ruby
# frozen_string_literal: true

# @lat: [[local-store-uploads#Why the binary never passes through Expo]]
# @lat: [[local-store-uploads#Why the Play uploader uses only the standard library]]
# Usage: upload-android.rb [path/to/app.aab]

require "base64"
require "json"
require "net/http"
require "openssl"
require "uri"

MOBILE = File.expand_path("..", __dir__)
SERVICE_ACCOUNT = File.join(MOBILE, "credentials", "play-service-account.json")
SCOPE = "https://www.googleapis.com/auth/androidpublisher"
TRACK = ENV.fetch("PLAY_TRACK", "internal")

def die(message)
  warn "upload-android.rb: #{message}"
  exit 1
end

def newest_aab
  Dir[File.join(MOBILE, "*.aab")].max_by { |path| File.mtime(path) }
end

# @lat: [[local-store-uploads#Why the Play upload mints its own access token]]
def access_token(service_account)
  now = Time.now.to_i
  header = {alg: "RS256", typ: "JWT"}
  claims = {
    iss: service_account.fetch("client_email"),
    scope: SCOPE,
    aud: service_account.fetch("token_uri"),
    iat: now,
    exp: now + 3600
  }
  signing_input = [header, claims].map { |part| Base64.urlsafe_encode64(JSON.dump(part), padding: false) }.join(".")
  key = OpenSSL::PKey::RSA.new(service_account.fetch("private_key"))
  signature = Base64.urlsafe_encode64(key.sign(OpenSSL::Digest.new("SHA256"), signing_input), padding: false)

  response = Net::HTTP.post_form(
    URI(service_account.fetch("token_uri")),
    "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer",
    "assertion" => "#{signing_input}.#{signature}"
  )
  die("token request failed: #{response.code} #{response.body}") unless response.is_a?(Net::HTTPSuccess)
  JSON.parse(response.body).fetch("access_token")
end

def request(token, method, url, body: nil, content_type: "application/json", binary: nil)
  uri = URI(url)
  klass = {get: Net::HTTP::Get, post: Net::HTTP::Post, put: Net::HTTP::Put}.fetch(method)
  req = klass.new(uri)
  req["Authorization"] = "Bearer #{token}"
  req["Content-Type"] = content_type
  if binary
    req.body_stream = File.open(binary, "rb")
    req["Content-Length"] = File.size(binary).to_s
  elsif body
    req.body = JSON.dump(body)
  end

  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, read_timeout: 900) { |http| http.request(req) }
  unless response.is_a?(Net::HTTPSuccess)
    die("#{method.to_s.upcase} #{uri.path} failed: #{response.code} #{response.body}")
  end
  response.body.to_s.empty? ? {} : JSON.parse(response.body)
end

aab = ARGV[0] || newest_aab
if aab.nil? || !File.size?(aab)
  die("no .aab given and none found in mobile/. Build one first:\n" \
      "  pnpm --dir mobile build:local -- --platform android --profile production")
end
unless File.size?(SERVICE_ACCOUNT)
  die("missing #{SERVICE_ACCOUNT.delete_prefix("#{MOBILE}/")}. Create a service account in Google Cloud, " \
      "grant it release access in Play Console under Users and permissions, and save its JSON key there.")
end

service_account = JSON.parse(File.read(SERVICE_ACCOUNT))
package = ENV["APPLE_BUNDLE_ID"] || die("APPLE_BUNDLE_ID is unset; it is also the Android package name")

token = access_token(service_account)
base = "https://androidpublisher.googleapis.com/androidpublisher/v3/applications/#{package}"

edit_id = request(token, :post, "#{base}/edits").fetch("id")
puts "opened Play edit #{edit_id}"

bundle = request(
  token, :post,
  "https://androidpublisher.googleapis.com/upload/androidpublisher/v3/applications/#{package}/edits/#{edit_id}/bundles?uploadType=media",
  content_type: "application/octet-stream",
  binary: aab
)
version_code = bundle.fetch("versionCode")
puts "uploaded #{File.basename(aab)} as version code #{version_code}"

request(
  token, :put, "#{base}/edits/#{edit_id}/tracks/#{TRACK}",
  body: {track: TRACK, releases: [{versionCodes: [version_code.to_s], status: "completed"}]}
)
request(token, :post, "#{base}/edits/#{edit_id}:commit")
puts "committed to the #{TRACK} track"
