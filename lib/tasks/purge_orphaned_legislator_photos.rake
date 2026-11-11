# frozen_string_literal: true

namespace :sway do
  namespace :assets do
    desc "Purge orphaned Legislator photo attachments from Active Storage"
    task :purge_orphaned_legislator_photos, [:force] => :environment do |_task, args|
      force = args[:force].to_s == "force"
      stats = LegislatorPhotoPurger.purge_orphans(force:)
      message = "purged #{stats[:purged_orphan_photo_attachments]} orphan legislator photos; " \
        "remaining=#{stats[:orphan_photo_attachments_after]}"

      SwayLogging.info("purge_orphaned_legislator_photos.rake - #{message} force=#{force}")
      puts(message)
    end
  end
end
