# frozen_string_literal: true

# @lat: [[seed-legislator-run-orchestration#One reconcile enqueue per locale]]
class ReconcileUserDistrictsJob < ApplicationJob
  queue_as :background

  def perform(sway_locale_id)
    sway_locale = SwayLocale.find_by(id: sway_locale_id)
    if sway_locale.nil?
      SwayLogging.warn("reconcile_user_districts_job.locale_not_found", sway_locale_id: sway_locale_id)
      return
    end

    User.joins(:address).distinct.find_each do |user|
      next unless user.sway_locales.include?(sway_locale)

      ReconcileUserDistrictsService.new(user, sway_locale).call
    rescue => e
      SwayLogging.log_exception(
        "reconcile_user_districts_job.user_failed",
        exception: e,
        user_id: user.id,
        sway_locale: sway_locale.name
      )
      Sentry.capture_exception(e, extra: {user_id: user.id, sway_locale: sway_locale.name})
      user.add_pending_representative_locale(sway_locale)
      next
    end
  end
end
