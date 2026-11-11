# frozen_string_literal: true

# @lat: [[mirrors-external-asset-concern#When the copy job is skipped]]
module MirrorsExternalAsset
  extend ActiveSupport::Concern

  class_methods do
    # @lat: [[mirrors-external-asset-concern#When the copy job is skipped]]
    def mirrors_external_asset(attachment_name:, url_column:)
      after_commit(if: :"saved_change_to_#{url_column}?") do
        enqueue_external_asset_mirroring(attachment_name: attachment_name, url_column: url_column)
      end
    end
  end

  private

  def enqueue_external_asset_mirroring(attachment_name:, url_column:)
    return if id.blank?
    return if internal_asset_url?(public_send(url_column))

    MirrorExternalAssetJob.perform_later(
      record_class_name: self.class.name,
      record_id: id,
      attachment_name: attachment_name,
      url_column: url_column
    )
  end

  def internal_asset_url?(url)
    return true if url.blank?

    uri = URI.parse(url)
    # @lat: [[mirrors-external-asset-concern#When the copy job is skipped#Why a blank host counts as already-internal]]
    return true if uri.host.blank?
    return false unless uri.is_a?(URI::HTTP)

    host = uri.host.to_s.downcase
    host == "sway.vote" || host.end_with?(".sway.vote") ||
      (
        host == "storage.googleapis.com" &&
          uri.path.to_s.start_with?("/#{SwayGoogleCloudStorage::BUCKETS[:ASSETS]}/")
      )
  rescue URI::InvalidURIError
    false
  end
end
