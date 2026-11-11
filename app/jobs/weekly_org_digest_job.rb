# frozen_string_literal: true

class WeeklyOrgDigestJob < ApplicationJob
  queue_as :background

  # @lat: [[org-digest-jobs-concurrency#Why the org digest jobs limit concurrency to one run]]
  limits_concurrency to: 1, key: "org_digest_weekly", on_conflict: :discard

  def perform
    DigestOrgNotificationAggregator.dispatch_period(:weekly)
  end
end
