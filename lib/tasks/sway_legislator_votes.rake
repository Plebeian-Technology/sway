# frozen_string_literal: true

# @lat: [[legislator-votes-update-rake-task#Legislator-votes update rake task]]
namespace :sway do
  namespace :legislator_votes do
    desc "Refresh legislator votes for all bills (or scoped to a single locale by name)"
    task :update, [:locale] => :environment do |_t, args|
      locale_name = args[:locale].presence

      sway_locale = nil
      if locale_name
        sway_locale = SwayLocale.find_by_name_parts(locale_name) # rubocop:disable Rails/DynamicFindBy
        if sway_locale.nil?
          SwayLogging.error("legislator_votes:update — no SwayLocale matches #{locale_name}")
          abort("No SwayLocale matches #{locale_name}")
        end
      end

      scope = sway_locale ? Bill.where(sway_locale: sway_locale) : Bill.all
      stats = Hash.new(0)
      skipped = []
      errors = []
      consecutive_errors = 0

      scope.find_each do |bill|
        # @lat: [[legislator-votes-update-rake-task#Why run_service_for, not perform_now]]
        LegislatorVoteFetchJob.run_service_for(bill.id)
        consecutive_errors = 0
        stats[:updated] += 1
        SwayLogging.info(
          "legislator_votes:update — ok bill_id=#{bill.id} external_id=#{bill.external_id} locale=#{bill.sway_locale.name}"
        )
      # @lat: [[legislator-votes-update-rake-task#Circuit breaker and permanent refusals]]
      rescue Scraper::Congress::RollCallNotOnTheBill, Scraper::Congress::RollCallMismatch => e
        stats[:skipped] += 1
        skipped << {bill_id: bill.id, error: e.message}
        SwayLogging.warn("legislator_votes:update — skipped bill_id=#{bill.id}: #{e.message}")
      rescue => e
        consecutive_errors += 1
        errors << {bill_id: bill.id, error: e.message}
        SwayLogging.error("legislator_votes:update — error bill_id=#{bill.id}: #{e.message}")
        if consecutive_errors >= 3
          SwayLogging.error("legislator_votes:update — 3 consecutive errors, aborting")
          break
        end
      end

      SwayLogging.info("legislator_votes:update — stats=#{stats}")
      if skipped.any?
        SwayLogging.info("legislator_votes:update — #{skipped.size} bill(s) skipped: #{skipped.inspect}")
      end
      if errors.any?
        SwayLogging.error("legislator_votes:update — #{errors.size} error(s): #{errors.inspect}")
        exit(1)
      end
    end
  end
end
