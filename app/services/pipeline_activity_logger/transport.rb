# frozen_string_literal: true

# @lat: [[pipeline-activity-logger-overview#Transport: two delivery paths, and safety nets for both]]
# @lat: [[pipeline-activity-logger-overview#Transport: why delivery must stay on the request's own thread]]
# @lat: [[pipeline-activity-log-error-banner-fallback#Why each delivery path has its own rescue]]
class PipelineActivityLogger
  module Transport
    # @lat: [[pipeline-activity-logger-overview#How PipelineActivityLogEntry triggers delivery]]
    def self.dispatch(entry)
      req = Current.request
      if req && inertia_request?(req)
        dispatch_inertia(entry, req)
      else
        dispatch_async(entry)
      end
    end

    # @lat: [[pipeline-activity-log-serialize-entry-quirks#Dropping the raw response for flash]]
    def self.dispatch_inertia(entry, req)
      req.flash[:activity_log_entry] = PipelineActivityLogger.serialize_entry(entry, for_flash: true) if req.respond_to?(:flash)
    rescue => e
      SwayLogging.log_exception(
        "pipeline_activity_log.flash_transport_failed",
        exception: e,
        level: :warn,
        entry_id: entry.id,
        event_type: entry.event_type,
        subject_type: entry.subject_type,
        subject_id: entry.subject_id
      )
      # @lat: [[pipeline-activity-log-error-banner-fallback#Why each delivery path has its own rescue]]
      if req.respond_to?(:flash)
        begin
          req.flash[:activity_log_error] = {entry_id: entry.id, error_class: e.class.name}
        rescue => e2
          # @lat: [[pipeline-activity-log-error-banner-fallback#Why a doubled failure logs both error classes on one line]]
          SwayLogging.error(
            "pipeline_activity_log.both_flash_transports_failed",
            entry_id: entry.id,
            event_type: entry.event_type,
            primary_error_class: e.class.name,
            secondary_error_class: e2.class.name
          )
        end
      end
    end
    private_class_method :dispatch_inertia

    # @lat: [[pipeline-activity-logger-overview#Transport: why dispatch_async also writes a log line]]
    def self.dispatch_async(entry)
      SwayLogging.info(
        "[PipelineActivityLog] #{entry.severity.to_s.upcase} " \
        "#{entry.event_type} ##{entry.id} #{entry.message.to_s[0, 240]}"
      )
      stream_id = resolve_stream_id(entry)
      # @lat: [[legislation-pipeline-run-broadcast-status-change#Why PipelineRunBroadcast.deliver never lets a failure propagate]]
      PipelineRunBroadcast.deliver(
        stream_id,
        {event: "activity_log_entry", entry: PipelineActivityLogger.serialize_entry(entry)},
        log_event: "pipeline_activity_log.cable_transport_failed",
        entry_id: entry.id,
        event_type: entry.event_type
      )
    end
    private_class_method :dispatch_async

    def self.inertia_request?(req)
      # @lat: [[pipeline-activity-logger-overview#Transport: why inertia_request? has its own rescue]]
      req.respond_to?(:inertia?) && req.inertia?
    rescue
      false
    end
    private_class_method :inertia_request?

    def self.resolve_stream_id(entry)
      case entry.subject_type
      when "LegislationPipelineRun"
        entry.subject&.remote_run_id || "global"
      when "Bill"
        entry.subject
          &.legislation_pipeline_runs
          &.order(created_at: :desc)
          &.first
          &.remote_run_id || "global"
      else
        "global"
      end
    end
    private_class_method :resolve_stream_id
  end
end
