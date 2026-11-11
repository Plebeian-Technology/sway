# frozen_string_literal: true

# @lat: [[sway-google-cloud-storage#A mirrored photo keeps its source address]]
namespace :sway do
  namespace :assets do
    desc "Reset legislator.photo_url from seed JSON"
    task :reset_photo_urls, [:locale] => :environment do |_t, args|
      force = ENV["FORCE"].to_s == "1"
      locale_name = args[:locale].presence

      sway_locale = nil
      if locale_name
        sway_locale = SwayLocale.find_by_name_parts(locale_name) # rubocop:disable Rails/DynamicFindBy
        if sway_locale.nil?
          SwayLogging.error("reset_photo_urls — no SwayLocale matches LOCALE=#{locale_name}")
          abort("No SwayLocale matches LOCALE=#{locale_name}")
        end
      end

      seeds_dir = Rails.root.join("db", "seeds", "data")
      seed_files = Dir.glob(seeds_dir.join("**", "legislators*.json"))

      seed_index = {}
      seed_files.each do |path|
        records = JSON.parse(File.read(path))
        records.each do |record|
          external_id = record["external_id"] || record["externalId"] || record["bioguideId"] || record["id"]
          next if external_id.blank?

          photo_url = record["photoUrl"] || record["photo_url"] ||
            record.dig("depiction", "imageUrl") ||
            record["image"]
          seed_index[external_id] = photo_url if photo_url.present?
        end
      end

      SwayLogging.info("reset_photo_urls — indexed #{seed_index.size} seed photoUrls from #{seed_files.size} files")

      scope = force ? Legislator.all : Legislator.where("photo_url LIKE ?", "%/rails/active_storage/%")
      if sway_locale
        scope = scope.where(sway_locale: sway_locale)
      end
      SwayLogging.info("reset_photo_urls — scope size=#{scope.count} force=#{force} locale=#{sway_locale&.name || "all"}")
      stats = Hash.new(0)

      scope.find_each do |leg|
        seed_url = seed_index[leg.external_id]

        if seed_url.blank?
          stats[:no_seed_match] += 1
          next
        end

        if leg.photo_url == seed_url
          stats[:already_correct] += 1
        else
          leg.update!(photo_url: seed_url)
          stats[:reset] += 1
          SwayLogging.info(
            "reset_photo_urls — reset id=#{leg.id} name=#{leg.full_name.inspect} locale=#{leg.sway_locale.name}"
          )
        end

        # @lat: [[sway-google-cloud-storage#Historical photo URLs are retired by exact identity]]
        leg.reload
        leg.update_columns(last_seeded_at: leg.updated_at)
        stats[:last_seeded_at_reset] += 1
      end

      SwayLogging.info("reset_photo_urls — stats=#{stats}")
    end
  end
end
