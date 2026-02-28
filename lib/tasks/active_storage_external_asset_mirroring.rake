namespace :sway do
  namespace :assets do
    desc "Mirror external organization/sway_locale/legislator assets to ActiveStorage"
    task mirror_external_assets: :environment do
      stats = Hash.new(0)

      mirror_scope(Organization.all, :icon, :icon_url, stats:)
      mirror_scope(SwayLocale.all, :icon, :icon_url, stats:)
      mirror_scope(Legislator.all, :photo, :photo_url, stats:)

      Rails.logger.info("mirror_external_assets.rake - stats=#{stats}")
      puts("mirror_external_assets.rake - stats=#{stats}")
    end

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
            url_column: url_column.to_s,
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
      "https://storage.googleapis.com/sway-assets/#{normalized_path}"
    rescue URI::InvalidURIError
      source_url
    end
  end
end
