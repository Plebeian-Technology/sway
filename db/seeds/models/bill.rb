# frozen_string_literal: true

require_relative "../seedable"

# @lat: [[legislation-pipeline#The stage graph]]
class SeedBill
  # Kept because lib/tasks/db_seed_force.rake (and possibly callers outside
  # this repo) still rescue this error class.
  class ServiceUnreachableError < StandardError; end

  # How many bills to seed is configurable (default 10) so operators can
  # choose fewer or more.
  DEFAULT_MAX_SEEDED_BILLS = 10

  # @lat: [[legislation-pipeline#Runs, resume and restart#Seeding trims each locale back to a fixed number of bills]]
  def self.resolve_max_seeded_bills(raw)
    n = raw.to_i
    n.positive? ? n : DEFAULT_MAX_SEEDED_BILLS
  end

  MAX_SEEDED_BILLS = resolve_max_seeded_bills(ENV.fetch("SEED_MAX_BILLS", DEFAULT_MAX_SEEDED_BILLS.to_s))
  BALTIMORE_LOCALE_NAME = "baltimore-maryland-united_states"

  class << self
    include Seedable

    # @param sway_locales [Array<SwayLocale>]
    # @param force [Boolean] when true, skips the count check so seeding runs
    #   even if the locale already has MAX_SEEDED_BILLS or more bills.
    # @param refresh [Boolean] when true, tells the pipeline to re-fetch
    #   upstream data instead of using what it already downloaded.
    # @return [Array<String>|nil] external_ids of seeded bills, or nil when skipped.
    def run(sway_locales, force: false, refresh: false)
      return nil unless enabled?

      sway_locale = sway_locales.find { |locale| locale.name == BALTIMORE_LOCALE_NAME }
      return nil if sway_locale.nil?

      if !force && Bill.where(sway_locale: sway_locale).count >= MAX_SEEDED_BILLS
        Rails.logger.info(
          "SeedBill: #{sway_locale.name} already has ≥#{MAX_SEEDED_BILLS} bills — skipping. " \
          "Pass force: true to reseed."
        )
        return nil
      end

      # The pipeline service calls this option download_missing_assets:, but
      # the seed API still accepts the older refresh: name for backward
      # compatibility (renaming the seed-side flag is tracked separately).
      # Translate the old name to the new one here.
      run_pipeline_synchronously!(sway_locale, download_missing_assets: refresh)

      # @lat: [[legislation-pipeline#Runs, resume and restart#Seeding trims each locale back to a fixed number of bills]]
      over_cap = Bill
        .where(sway_locale: sway_locale)
        .order(introduced_date_time_utc: :desc)
        .offset(MAX_SEEDED_BILLS)
        .to_a
      if over_cap.any?
        over_cap_ids = over_cap.map(&:id)
        # @lat: [[legislation-pipeline#Runs, resume and restart#Seeding trims each locale back to a fixed number of bills]]
        [UserVote, UserLegislatorEmail, UserBillReminder, AdminBillView].each do |model|
          model.where(bill_id: over_cap_ids).delete_all
        end
        over_cap.each(&:destroy)
        Rails.logger.info(
          "SeedBill: trimmed #{over_cap.size} bill(s) over the " \
          "#{MAX_SEEDED_BILLS}-bill cap for #{sway_locale.name}"
        )
      end

      Bill
        .where(sway_locale: sway_locale)
        .order(introduced_date_time_utc: :desc)
        .limit(MAX_SEEDED_BILLS)
        .pluck(:external_id)
    rescue => e
      Rails.logger.error "Error seeding bills: #{e.message}\n#{e.backtrace&.join("\n")}"
      raise unless Rails.env.test?
      nil
    end

    def enabled?
      Rails.env.local? || preview_database?
    end

    def preview_database?
      ENV.fetch("SWAY_DATABASE_NAME", "").include?("preview.sqlite3")
    end

    private

    # @lat: [[legislation-pipeline#Runs, resume and restart#Seeding fails loudly when a pipeline run does not succeed]]
    def terminal_success_for_seed
      @terminal_success_for_seed ||=
        (LegislationPipelineRun::TERMINAL_SUCCESS_STATUSES + %w[partial]).freeze
    end

    def run_pipeline_synchronously!(sway_locale, download_missing_assets: true)
      stages = LegislationPipelineRun::ALLOWED_PIPELINE_STAGES
      run = LegislationPipelineRunService.new(
        stages: stages,
        sway_locale: sway_locale,
        download_missing_assets: download_missing_assets
      ).call(skip_enqueue: true)

      RunLegislationPipelineJob.perform_now(run.id, origin: "seed")
      status_after = run.reload.status
      SwayLogging.info(
        "pipeline_completed",
        run_id: run.id,
        status: status_after
      )

      # Success means :completed, :succeeded, or :partial (partial = at least
      # one bill made it through, a legitimate seed outcome). Anything else —
      # failed, cancelled, or stuck in :queued because a state-machine guard
      # hit a pre-existing failed row — counts as a seed failure.
      unless terminal_success_for_seed.include?(status_after.to_s)
        raise ServiceUnreachableError,
          "SeedBill: pipeline did not reach terminal-success " \
          "(run ##{run.id} status=#{status_after.inspect}). " \
          "Inspect the activity log for the underlying failure."
      end
    end
  end
end
