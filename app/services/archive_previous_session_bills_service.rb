# frozen_string_literal: true

class ArchivePreviousSessionBillsService
  def initialize(sway_locale:)
    @sway_locale = sway_locale
  end

  # @lat: [[bill-session-archiving#Bill session archiving#Eligibility]]
  def candidates
    session = current_session
    cutoff = session.start_date.beginning_of_day
    prior_sessions = @sway_locale.legislative_sessions
      .where(active: false)
      .where("start_date < ? AND end_date <= ?", session.start_date, session.start_date)
    base = Bill.where(sway_locale: @sway_locale, scheduled_release_date_utc: nil)
      .where("introduced_date_time_utc <= ?", Time.current)

    base.where(legislative_session_id: prior_sessions.select(:id))
      .or(base.where(legislative_session_id: nil).where("introduced_date_time_utc < ?", cutoff))
  end

  # @lat: [[bill-session-archiving#Bill session archiving#Preserved history]]
  def call
    # @lat: [[bill-session-archiving#Bill session archiving#Pipeline and archive exclusion]]
    PipelineLocaleLock.with_locale(@sway_locale.id, wait: false) do
      Bill.transaction do
        busy = LegislationPipelineRun.active_any
          .where(sway_locale_id: [@sway_locale.id, nil]).where.not(status: "queued").exists?
        raise PipelineLocaleLock::Busy, "Pipeline is busy for #{@sway_locale.name}; archiving refused" if busy

        timestamp = Time.current
        candidates.update_all(archived_at: timestamp, updated_at: timestamp)
      end
    end
  end

  def current_session
    session = @sway_locale.legislative_sessions.active.order(start_date: :desc).first ||
      raise(ArgumentError, "#{@sway_locale.name} has no active legislative session")
    raise ArgumentError, "#{session.name} has not started" if session.start_date > Date.current

    session
  end
end
