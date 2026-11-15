# frozen_string_literal: true

# @lat: [[registration-dead-ends#A skipped lookup is recorded so it can be retried#The hourly job assigns what was skipped]]
class AssignPendingRepresentativesJob < ApplicationJob
  queue_as :background

  def perform
    failures_by_locale = {} #: Hash[String, { error: StandardError, failed_users: Integer }]

    User.where("json_array_length(pending_representative_locale_ids) > 0").find_each do |user|
      located = address_located?(user)

      SwayLocale.where(id: user.pending_representative_locale_ids).each do |sway_locale|
        ReconcileUserDistrictsService.new(user, sway_locale).call
        user.remove_pending_representative_locale(sway_locale) if located && user.user_legislators.where(active: true).exists?
      rescue => e
        SwayLogging.log_exception(
          "assign_pending_representatives_job.user_failed",
          exception: e,
          user_id: user.id,
          sway_locale: sway_locale.name
        )
        failure = failures_by_locale[sway_locale.name] ||= {error: e, failed_users: 0}
        failure[:failed_users] += 1
      end
    end

    failures_by_locale.each do |sway_locale_name, failure|
      Sentry.capture_exception(failure[:error], extra: {sway_locale: sway_locale_name, failed_users: failure[:failed_users]})
    end
  end

  private

  # @lat: [[registration-dead-ends#A skipped lookup is recorded so it can be retried#An unlocated address waits for its geocode]]
  def address_located?(user)
    address = user.address
    return true if address.nil? || address.located?

    address.geocode_and_save
    return false unless address.located?

    address.sway_locales.each { |sway_locale| user.add_pending_representative_locale(sway_locale) }
    true
  rescue => e
    SwayLogging.log_exception("assign_pending_representatives_job.locate_failed", exception: e, user_id: user.id)
    Sentry.capture_exception(e, extra: {user_id: user.id})
    false
  end
end
