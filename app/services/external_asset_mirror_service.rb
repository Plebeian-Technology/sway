# frozen_string_literal: true

require "resolv"
require "ipaddr"
require "net/http"

class ExternalAssetMirrorService
  STORAGE_HOST = "storage.googleapis.com"
  # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService#Why ASSETS_BUCKET is not named here]]
  ASSETS_BUCKET = SwayGoogleCloudStorage::BUCKETS[:ASSETS]

  # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
  MAX_DOWNLOAD_BYTES = 10 * 1024 * 1024

  ALLOWED_IMAGE_CONTENT_TYPES = %w[
    image/jpeg
    image/png
    image/webp
    image/gif
    image/svg+xml
    image/avif
  ].freeze

  # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
  RESERVED_INTERNAL_RANGES = [
    IPAddr.new("0.0.0.0/8"),
    IPAddr.new("10.0.0.0/8"),
    IPAddr.new("100.64.0.0/10"),
    IPAddr.new("127.0.0.0/8"),
    IPAddr.new("169.254.0.0/16"),
    IPAddr.new("172.16.0.0/12"),
    IPAddr.new("192.0.0.0/24"),
    IPAddr.new("192.0.2.0/24"),
    IPAddr.new("192.168.0.0/16"),
    IPAddr.new("198.18.0.0/15"),
    IPAddr.new("198.51.100.0/24"),
    IPAddr.new("203.0.113.0/24"),
    IPAddr.new("224.0.0.0/4"),
    IPAddr.new("240.0.0.0/4"),
    IPAddr.new("255.255.255.255/32"),
    IPAddr.new("::/128"),
    IPAddr.new("::1/128"),
    IPAddr.new("2001:db8::/32"),
    IPAddr.new("fc00::/7"),
    IPAddr.new("fe80::/10"),
    IPAddr.new("ff00::/8")
  ].freeze

  class << self
    def call(record:, attachment_name:, url_column:)
      source_url = record.public_send(url_column)
      return :skipped if source_url.blank?
      return :skipped if non_http_url?(source_url)
      return :skipped if internal_asset_url?(source_url)
      # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
      return :skipped if Rails.env.production? && private_or_local_host?(source_url)

      if Sway::Settings.ops.is_docker && source_url.include?("localhost")
        source_url = record.public_send(url_column).gsub("https://", "http://").gsub("localhost", "web")
      end
      # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
      source_url = safe_normalize_url(source_url)
      # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
      final_url = resolve_final_url(source_url)
      return :skipped if final_url.nil?

      return :failed_soft unless attach_download(record, attachment_name, final_url, source_url)

      # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
      :mirrored
    rescue Down::NotFound => e
      # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
      purge_attachment(record, attachment_name)
      SwayLogging.warn(
        "ExternalAssetMirrorService.call upstream 404 record=#{record.class.name} id=#{record.id} url_column=#{url_column} url=#{record.public_send(url_column)} error=#{e.message}"
      )
      :upstream_not_found
    rescue => e
      SwayLogging.warn(
        "ExternalAssetMirrorService.call failed record=#{record.class.name} id=#{record.id} url_column=#{url_column} error=#{e.class}: #{e.message}"
      )
      :failed_soft
    end

    private

    def attach_download(record, attachment_name, final_url, source_url)
      downloaded_file = Down.download(final_url, max_size: MAX_DOWNLOAD_BYTES, max_redirects: 0)
      begin
        media_type = downloaded_file.content_type.to_s.split(";").first.to_s.strip.downcase
        return false unless ALLOWED_IMAGE_CONTENT_TYPES.include?(media_type)

        attachment = record.public_send(attachment_name)
        attachment.attach(
          io: downloaded_file,
          filename: mirror_filename(downloaded_file, source_url),
          content_type: media_type
        )
        attachment.attached?
      ensure
        downloaded_file.close!
      end
    end

    # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService#Why URLs are normalized before download]]
    def safe_normalize_url(url)
      Addressable::URI.parse(url).normalize.to_s
    rescue Addressable::URI::InvalidURIError
      url
    end

    # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
    def resolve_final_url(url, max_hops: 2)
      current = url
      (max_hops + 1).times do
        resolved_ip = Rails.env.production? ? resolve_public_ip(URI.parse(current).host.to_s) : nil
        return nil if Rails.env.production? && resolved_ip.nil?

        location = redirect_location_for(current, resolved_ip: resolved_ip)
        return current if location.nil?

        nxt = absolute_redirect_target(current, location)
        return nil if nxt.nil?
        return nil if non_http_url?(nxt) || internal_asset_url?(nxt) ||
          (Rails.env.production? && private_or_local_host?(nxt))

        current = nxt
      end
      nil
    end

    # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
    def redirect_location_for(url, resolved_ip: nil)
      uri = URI.parse(url)
      host = uri.host.to_s
      resolved_ip = resolve_public_ip(host) if Rails.env.production? && resolved_ip.nil?
      return nil if Rails.env.production? && resolved_ip.nil?

      location = nil #: String?
      http = Net::HTTP.new(host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = 5
      http.read_timeout = 10
      http.ipaddr = resolved_ip if resolved_ip.present?
      http.start do |conn|
        conn.request(Net::HTTP::Get.new(uri)) do |response|
          location = response["location"].to_s.presence if response.is_a?(Net::HTTPRedirection)
          conn.finish if conn.started?
          return location
        end
      end
      location
    rescue => e
      # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
      SwayLogging.warn(
        "ExternalAssetMirrorService.redirect_location_for probe failed url=#{url} error=#{e.class}: #{e.message}"
      )
      nil
    end

    # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
    def absolute_redirect_target(base, location)
      URI.join(base, safe_normalize_url(location)).to_s
    rescue URI::InvalidURIError, ArgumentError
      nil
    end

    def non_http_url?(url)
      uri = URI.parse(url)
      !uri.is_a?(URI::HTTP)
    rescue URI::InvalidURIError
      true
    end

    def internal_asset_url?(url)
      uri = URI.parse(url)
      host = uri.host.to_s.downcase

      path = uri.path.to_s

      host == "sway.vote" || host.end_with?(".sway.vote") ||
        (host == STORAGE_HOST && path.start_with?("/#{ASSETS_BUCKET}/"))
    rescue URI::InvalidURIError
      false
    end

    # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
    def private_or_local_host?(url)
      host = URI.parse(url).host.to_s
      resolve_public_ip(host).nil?
    rescue URI::InvalidURIError
      true
    end

    def resolve_public_ip(host)
      return nil if host.blank?

      addresses = host_addresses(host)
      return nil if addresses.empty?
      return nil if addresses.any? { |address| blocked_ip_address?(address) }

      addresses.first
    rescue IPAddr::InvalidAddressError, Resolv::ResolvError
      nil
    end

    def blocked_ip_address?(address)
      ip = IPAddr.new(address)
      ip.private? || ip.loopback? || ip.link_local? ||
        RESERVED_INTERNAL_RANGES.any? { |range| range.include?(ip) }
    rescue IPAddr::InvalidAddressError
      true
    end

    # @lat: [[external-asset-mirroring-design#ExternalAssetMirrorService]]
    def host_addresses(host)
      [IPAddr.new(host).to_s]
    rescue IPAddr::InvalidAddressError
      Resolv.getaddresses(host)
    end

    def mirror_filename(downloaded_file, source_url)
      filename = File.basename(URI.parse(source_url).path.to_s)
      return filename if filename.present? && filename != "/"

      if downloaded_file.respond_to?(:original_filename) &&
          downloaded_file.original_filename.present?
        downloaded_file.original_filename
      else
        "mirror-#{SecureRandom.hex(8)}"
      end
    rescue URI::InvalidURIError
      "mirror-#{SecureRandom.hex(8)}"
    end

    def purge_attachment(record, attachment_name)
      attachment = record.public_send(attachment_name)
      return unless attachment.attached?

      attachment.purge
    end
  end
end
