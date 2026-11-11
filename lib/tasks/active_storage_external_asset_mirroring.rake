module ExternalAssetMirroringRakeHelpers
  module_function

  def mirror_scope(scope, attachment_name, url_column, stats:)
    scope.find_each do |record|
      source_url = record.public_send(url_column)
      next if source_url.blank?

      normalized_url = normalize_source_url(source_url)
      if normalized_url != source_url
        record.update!(url_column => normalized_url)
        normalized_url
      end

      result =
        ExternalAssetMirrorService.call(
          record:,
          attachment_name: attachment_name.to_s,
          url_column: url_column.to_s
        )

      case result
      when :mirrored
        stats["mirrored"] += 1
      when :cleared_not_found
        stats["cleared_404"] += 1
      when :failed_soft
        stats["failed_soft"] += 1
      else
        stats["skipped"] += 1
      end
    end
  end

  def normalize_source_url(source_url)
    uri = URI.parse(source_url)
    return source_url if uri.is_a?(URI::HTTP)

    normalized_path = source_url.delete_prefix("/")
    "https://storage.googleapis.com/#{SwayGoogleCloudStorage::BUCKETS[:ASSETS]}/#{normalized_path}"
  rescue URI::InvalidURIError
    source_url
  end
end

namespace :sway do
  namespace :assets do
    desc "Mirror external organization/legislator assets to ActiveStorage"
    # @lat: [[sway-google-cloud-storage#Only consumers of mirrored assets declare the callback]]
    task mirror_external_assets: :environment do
      stats = Hash.new(0)

      ExternalAssetMirroringRakeHelpers.mirror_scope(Organization.all, :icon, :icon_url, stats:)
      ExternalAssetMirroringRakeHelpers.mirror_scope(Legislator.all, :photo, :photo_url, stats:)

      SwayLogging.info("mirror_external_assets.rake - stats=#{stats}")
      puts("mirror_external_assets.rake - stats=#{stats}")
    end
  end
end
