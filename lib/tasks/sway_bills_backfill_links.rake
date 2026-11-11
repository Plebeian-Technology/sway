# frozen_string_literal: true

# @lat: [[legistar-detail-url-resolution#Backfill procedure for stored Baltimore bills]]
namespace :sway do
  namespace :bills do
    desc "Backfill stored Baltimore bills holding generic Legistar search address"
    task backfill_links: :environment do
      stats = BaltimoreBillLinkBackfillService.call
      puts "sway:bills:backfill_links - processed: #{stats[:processed]}, resolved: #{stats[:resolved]}, cleared: #{stats[:cleared]}, failed: #{stats[:failed]}"
      abort "sway:bills:backfill_links failed: #{stats[:failed]} persistence #{"failure".pluralize(stats[:failed])}" if stats[:failed].positive?
    end

    task backfill_baltimore_links: :backfill_links
  end
end
