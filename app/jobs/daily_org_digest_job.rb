# frozen_string_literal: true

class DailyOrgDigestJob < ApplicationJob
  queue_as :background

  # @lat: [[org-digest-jobs-concurrency#Why the org digest jobs limit concurrency to one run]]
  limits_concurrency to: 1, key: "org_digest_daily", on_conflict: :discard

  def perform
    DigestOrgNotificationAggregator.dispatch_period(:daily)
  end
end
