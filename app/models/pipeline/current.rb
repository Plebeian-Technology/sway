# frozen_string_literal: true

module Pipeline
  # @lat: [[pipeline-activity-log-auto-included-stage-context#Why Pipeline::Current uses ActiveSupport::CurrentAttributes, not Thread.current]]
  class Current < ActiveSupport::CurrentAttributes
    attribute :current_auto_include_context
  end
end
