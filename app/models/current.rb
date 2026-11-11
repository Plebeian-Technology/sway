# frozen_string_literal: true

# @lat: [[pipeline-activity-logger-overview#How the logger knows whether a page is about to render]]
class Current < ActiveSupport::CurrentAttributes
  attribute :request

  # @lat: [[current-legislator-term#Why the answer is worked out once per request]]
  attribute :current_legislator_term_ids
end
