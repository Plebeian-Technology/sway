# frozen_string_literal: true

# @lat: [[legislation-pipeline-run-broadcast-status-change#Why PipelineRunBroadcast.deliver never lets a failure propagate]]
module PipelineRunBroadcast
  def self.deliver(stream_id, payload, log_event:, **context)
    PipelineRunChannel.broadcast_to(stream_id, **payload)
    true
  rescue => e
    SwayLogging.log_exception(log_event, exception: e, level: :warn, stream_id: stream_id, **context)
    Sentry.capture_exception(e, extra: {log_event: log_event, stream_id: stream_id}.merge(context))
    false
  end
end
