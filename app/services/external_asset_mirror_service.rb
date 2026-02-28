# frozen_string_literal: true
# typed: true

class ExternalAssetMirrorService
  STORAGE_HOST = "storage.googleapis.com"
  ASSETS_BUCKET = "sway-assets"

  class << self
    def call(record:, attachment_name:, url_column:)
      source_url = record.public_send(url_column)
      return :skipped if source_url.blank?
      return :skipped if non_http_url?(source_url)
      return :skipped if internal_asset_url?(source_url)

      downloaded_file = Down.download(source_url)

      attachment = record.public_send(attachment_name)
      attachment.attach(
        io: downloaded_file,
        filename: mirror_filename(downloaded_file, source_url),
        content_type: downloaded_file.content_type,
      )

      return :failed_soft unless attachment.attached?

      internal_url = attached_asset_url(attachment)
      record.update!(url_column => internal_url)
      :mirrored
    rescue Down::NotFound
      purge_attachment(record, attachment_name)
      record.update!(url_column => nil)
      :cleared_not_found
    rescue StandardError => e
      Rails.logger.warn(
        "ExternalAssetMirrorService.call failed record=#{record.class.name} id=#{record.id} url_column=#{url_column} error=#{e.class}: #{e.message}",
      )
      :failed_soft
    ensure
      downloaded_file&.close!
    end

    private

    def non_http_url?(url)
      uri = URI.parse(url)
      !uri.is_a?(URI::HTTP)
    rescue URI::InvalidURIError
      true
    end

    def internal_asset_url?(url)
      uri = URI.parse(url)
      host = uri.host.to_s.downcase

      host.ends_with?("sway.vote") ||
        (host == STORAGE_HOST && uri.path.start_with?("/#{ASSETS_BUCKET}/"))
    rescue URI::InvalidURIError
      false
    end

    def mirror_filename(downloaded_file, source_url)
      filename = File.basename(URI.parse(source_url).path)
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

    def attached_asset_url(attachment)
      Rails.application.routes.url_helpers.rails_storage_proxy_url(
        attachment,
        **default_url_options,
      )
    end

    def default_url_options
      Rails.application.config.action_mailer.default_url_options ||
        Rails.application.routes.default_url_options ||
        { host: "localhost", protocol: "http" }
    end

    def purge_attachment(record, attachment_name)
      attachment = record.public_send(attachment_name)
      return unless attachment.attached?

      attachment.purge
    end
  end
end
