# frozen_string_literal: true

# @lat: [[pipeline-activity-logger-overview#How PipelineActivityLogEntry triggers delivery]]
class PipelineActivityLogger
  # @lat: [[pipeline-activity-logger-overview#Why delivery is triggered by an after-create hook, not a hand-written dispatcher]]

  # @lat: [[pipeline-activity-logger-overview#Why certain events carry a fixed severity]]
  SEVERITY_FOR_EVENT = {
    "stage_failed" => "error",
    "ingestion_failure" => "error",
    "llm_provider_error" => "error",
    "llm_json_parse_failure" => "error",
    "summary_regenerate_triggered" => "info",
    "state_transition" => "info",
    "bill_state_transition" => "info",
    "paste_summary_accepted" => "info",
    "paste_summary_rejected" => "warning",
    "org_position_decision" => "info",
    "orphan_run_deleted" => "info",
    "force_fail_triggered" => "warning",
    "stage_budget_tripped" => "warning",
    "summary_stood_down_for_paste" => "info",
    "summary_skipped_no_source_text" => "info",
    "resume_deferred_for_summary_batch" => "info",
    "attachment_download_attempt" => "info"
  }.freeze

  TITLE_TEMPLATES = {
    "stage_failed" => ->(p) { "Stage failed: #{p[:stage_name]}".first(60) },
    "ingestion_failure" => ->(_p) { "Bill ingestion failed" },
    "llm_provider_error" => ->(_p) { "LLM provider error" },
    "llm_json_parse_failure" => ->(_p) { "LLM response parse failed" },
    # @lat: [[pipeline-activity-log-summary-regenerate-event#Why one event covers "generate" and "regenerate"]]
    "summary_regenerate_triggered" => ->(p) {
      verb = p[:first_generation] ? "generation" : "regeneration"
      "Summary #{verb} triggered: #{p[:bill_external_id]}".first(60)
    },
    "state_transition" => ->(p) { "Run #{p[:from]} → #{p[:to]}".first(60) },
    "bill_state_transition" => ->(p) { "Bill #{p[:from]} → #{p[:to]}".first(60) },
    "paste_summary_accepted" => ->(p) { "Summary pasted: #{p[:bill_external_id]}".first(60) },
    "paste_summary_rejected" => ->(_p) { "Summary paste rejected" },
    "org_position_decision" => ->(p) { "Org position #{p[:decision]}: #{p[:org_name]}".first(60) },
    "orphan_run_deleted" => ->(p) { "Orphan run ##{p[:run_id]} removed".first(60) },
    "force_fail_triggered" => ->(_p) { "Run force-failed" },
    "stage_budget_tripped" => ->(p) { "Stage #{p[:stage]} aborted: budget tripped".first(60) },
    "summary_stood_down_for_paste" => ->(_p) { "Summary generation stood down (paste)" },
    "summary_skipped_no_source_text" => ->(_p) { "Summary generation skipped (no source text)" },
    "resume_deferred_for_summary_batch" => ->(_p) { "Resume deferred: summary batch still in flight" },
    "attachment_download_attempt" => ->(p) {
      outcome = p[:outcome] || p["outcome"] || p[:status] || p["status"] || "attempted"
      target = p[:attachment_id] || p["attachment_id"] || p[:filename] || p["filename"] || "attachment"
      "Attachment download #{outcome}: #{target}".first(60)
    }
  }.freeze

  # @lat: [[pipeline-activity-log-event-key-alignment#Why the event-key check runs at boot]]
  if SEVERITY_FOR_EVENT.keys.sort != TITLE_TEMPLATES.keys.sort
    raise "PipelineActivityLogger: SEVERITY_FOR_EVENT keys != TITLE_TEMPLATES keys " \
      "(in severity not templates: #{(SEVERITY_FOR_EVENT.keys - TITLE_TEMPLATES.keys).inspect}, " \
      "in templates not severity: #{(TITLE_TEMPLATES.keys - SEVERITY_FOR_EVENT.keys).inspect})"
  end

  def self.log_stage_failed!(run:, stage_name:, error_message:, actor: nil)
    payload = PipelineActivityLog::StageFailurePayload.new(
      stage_name: stage_name,
      error_message: error_message
    ).to_h
    message = "Run #{run.remote_run_id.to_s[0..7]} failed at #{stage_name} — #{error_message.to_s[0...200]}"
    emit!("stage_failed", subject: run, actor: actor, payload: payload, message: message)
  end

  def self.log_ingestion_failure!(bill_external_id:, error_message:, actor: nil)
    payload = PipelineActivityLog::IngestionFailurePayload.new(
      bill_external_id: bill_external_id,
      error_message: error_message
    ).to_h
    message = "Failed to ingest bill #{bill_external_id} — #{error_message.to_s[0...200]}"
    emit!("ingestion_failure", subject: nil, actor: actor, payload: payload, message: message)
  end

  def self.log_llm_provider_error!(bill:, error_message:, actor: nil)
    payload = PipelineActivityLog::LlmProviderErrorPayload.new(
      error_message: error_message
    ).to_h
    message = "LLM provider error for #{bill.external_id} — #{error_message.to_s[0...200]}"
    emit!("llm_provider_error", subject: bill, actor: actor, payload: payload, message: message)
  end

  def self.log_llm_json_parse_failure!(bill:, error_message:, raw_excerpt: nil, actor: nil)
    payload = PipelineActivityLog::LlmJsonParseFailurePayload.new(
      error_message: error_message,
      raw_excerpt: raw_excerpt.to_s
    ).to_h
    message = "LLM response for #{bill.external_id} could not be parsed — #{error_message.to_s[0...200]}"
    emit!("llm_json_parse_failure", subject: bill, actor: actor, payload: payload, message: message)
  end

  # @lat: [[pipeline-activity-log-summary-regenerate-event#Why one event covers "generate" and "regenerate"]]
  def self.log_summary_regenerate_triggered!(bill:, actor:, first_generation:)
    payload = PipelineActivityLog::SummaryRegenerateTriggeredPayload.new(
      bill_external_id: bill.external_id,
      bill_id: bill.id,
      first_generation: first_generation
    ).to_h
    verb = first_generation ? "summary generation" : "summary regeneration"
    message = "Operator triggered #{verb} for #{bill.external_id}"
    emit!("summary_regenerate_triggered", subject: bill, actor: actor, payload: payload, message: message)
  end

  # @lat: [[explanation/llm-summaries#Stand-downs are reported, not swallowed#The activity log names the stand-down and what to do about it]]
  def self.log_summary_stood_down_for_paste!(bill:, actor: nil)
    payload = {bill_id: bill.id, bill_external_id: bill.external_id}
    message = "Generation for #{bill.external_id} stood down: an operator already pasted a summary " \
      "onto this bill. The Regenerate button on the summary tab clears the paste; Run Pipeline will not."
    emit!("summary_stood_down_for_paste", subject: bill, actor: actor, payload: payload, message: message)
  end

  # @lat: [[explanation/llm-summaries#Stand-downs are reported, not swallowed#The activity log names the stand-down and what to do about it]]
  def self.log_summary_skipped_no_source_text!(bill:, actor: nil)
    payload = {bill_id: bill.id, bill_external_id: bill.external_id}
    message = "Generation for #{bill.external_id} was skipped: no extracted text and no diff markdown " \
      "to summarize. Run the pipeline's extract-text and fetch-hearings stages, then generate again."
    emit!("summary_skipped_no_source_text", subject: bill, actor: actor, payload: payload, message: message)
  end

  # @lat: [[explanation/llm-summaries#Batch summarisation#Why resume draws the same line as abandonment]]
  def self.log_resume_deferred_for_summary_batch!(run:, actor: nil)
    live = run.live_summary_batches
    batch_ids = live.map(&:batch_id)
    last_expiry = live.filter_map(&:expires_at).max
    payload = {
      run_id: run.id,
      summary_batch_ids: batch_ids,
      summary_batch_expires_at: last_expiry&.utc&.iso8601
    }
    message = "Resume for run ##{run.id} deferred: #{batch_ids.size} summary #{"batch".pluralize(batch_ids.size)} " \
      "still in flight (#{batch_ids.join(", ")}; last expiry #{last_expiry&.utc&.iso8601 || "unknown"}). " \
      "The run stays in awaiting_summary_batch; resuming again once they settle will normalize it as usual."
    emit!("resume_deferred_for_summary_batch", subject: run, actor: actor, payload: payload, message: message)
  end

  def self.log_paste_summary_accepted!(bill:, actor:)
    payload = {
      bill_external_id: bill.external_id,
      bill_id: bill.id,
      operator_email: actor_email(actor)
    }
    message = "Operator pasted summary for #{bill.external_id}"
    emit!("paste_summary_accepted", subject: bill, actor: actor, payload: payload, message: message)
  end

  def self.log_paste_summary_rejected!(bill:, actor:, errors:)
    payload = {
      bill_external_id: bill.external_id,
      bill_id: bill.id,
      operator_email: actor_email(actor),
      errors: Array(errors).map(&:to_s)
    }
    message = "Paste-back rejected for #{bill.external_id}: #{Array(errors).size} validation errors"
    emit!("paste_summary_rejected", subject: bill, actor: actor, payload: payload, message: message)
  end

  # @lat: [[pipeline-activity-logger-overview#Why log_org_position_decision! accepts a duck-typed draft]]
  def self.log_org_position_decision!(bill:, draft:, decision:, actor:, extra: {})
    org_name = draft.respond_to?(:organization_name) ? draft.organization_name.to_s : draft.to_s
    draft_id = draft.respond_to?(:id) ? draft.id : nil
    payload = {
      bill_id: bill.id,
      bill_external_id: bill.external_id,
      draft_id: draft_id,
      org_name: org_name,
      decision: decision.to_s,
      operator_email: actor_email(actor)
    }.merge(extra)
    message = "Org-position decision #{decision} for #{org_name} on #{bill.external_id}"
    emit!("org_position_decision", subject: bill, actor: actor, payload: payload, message: message)
  end

  def self.log_orphan_run_deleted!(run_id:, actor:)
    payload = {
      run_id: run_id,
      operator_email: actor_email(actor)
    }
    message = "Orphan run ##{run_id} removed by #{actor_email(actor) || "unknown"}"
    emit!("orphan_run_deleted", subject: nil, actor: actor, payload: payload, message: message)
  end

  def self.log_force_fail_triggered!(run:, actor:)
    payload = {
      run_id: run.id,
      remote_run_id: run.remote_run_id.to_s,
      operator_email: actor_email(actor)
    }
    message = "Run ##{run.id} force-failed by #{actor_email(actor) || "unknown"}"
    emit!("force_fail_triggered", subject: run, actor: actor, payload: payload, message: message)
  end

  # @lat: [[pipeline-activity-logger-overview#Why certain events carry a fixed severity]]
  def self.log_stage_budget_tripped!(run:, stage:, consecutive_failures:, last_failed_bill_run:)
    payload = {
      stage: stage.to_s,
      consecutive_failures: consecutive_failures,
      last_failed_bill_run_id: last_failed_bill_run.id,
      last_failed_bill_external_id: last_failed_bill_run.bill_external_id
    }
    message = "Stage #{stage} aborted after #{consecutive_failures} consecutive bill failures"
    emit!("stage_budget_tripped", subject: run, actor: nil, payload: payload, message: message)
  end

  def self.log_attachment_download_attempt!(record:, bill: nil, actor: nil)
    payload = {
      bill_id: bill&.id,
      bill_external_id: bill&.external_id,
      sway_locale_id: bill&.sway_locale_id,
      attachment_id: record["id"],
      filename: record["filename"],
      url: record["url"],
      status: record["download_status"],
      outcome: record["download_status"],
      error: record["error"],
      attempted_at: Time.current.iso8601
    }
    bill_label = bill&.external_id || "unassigned"
    message = "Attachment #{record["id"] || record["filename"]} download #{record["download_status"]} for #{bill_label}"
    message += " (#{record["error"][0, 100]})" if record["error"].present?
    emit!("attachment_download_attempt", subject: bill, actor: actor, payload: payload, message: message.first(250))
  end

  # @lat: [[pipeline-activity-log-auto-included-stage-context#Why Pipeline::Current uses ActiveSupport::CurrentAttributes, not Thread.current]]
  def self.emit_state_transition!(run:, from:, to:, event:)
    # @lat: [[explanation/rbs-signatures#Why a growing hash literal needs an inline annotation]]
    payload = {from: from.to_s, to: to.to_s, event: event.to_s, run_id: run.id} #: Hash[Symbol, untyped]
    ctx = Pipeline::Current.current_auto_include_context
    if event.to_s.start_with?("start_") && ctx.is_a?(Hash) && !ctx.empty?
      payload[:auto_included] = true
      payload[:stage] = ctx[:stage] if ctx.key?(:stage)
      payload[:reason] = ctx[:reason] if ctx.key?(:reason)
      payload[:bill_external_ids] = ctx[:bill_external_ids] if ctx.key?(:bill_external_ids)
    end
    message = "Run #{run.remote_run_id.to_s[0..7]} transitioned #{from} → #{to} via #{event}"
    emit!("state_transition", subject: run, actor: nil, payload: payload, message: message)
  end

  def self.emit_bill_transition!(bill_run:, from:, to:, event:)
    payload = {
      from: from.to_s,
      to: to.to_s,
      event: event.to_s,
      bill_run_id: bill_run.id,
      bill_external_id: bill_run.bill_external_id,
      legislation_pipeline_run_id: bill_run.legislation_pipeline_run_id
    }
    message = "Bill #{bill_run.bill_external_id} transitioned #{from} → #{to} via #{event}"
    emit!("bill_state_transition", subject: nil, actor: nil, payload: payload, message: message)
  end

  # @lat: [[pipeline-activity-log-serialize-entry-quirks#Why created_at is written with iso8601(6), not plain iso8601]]
  def self.serialize_entry(entry, for_flash: false)
    payload = entry.payload
    payload = payload.deep_stringify_keys if payload.is_a?(Hash)
    if for_flash && payload.is_a?(Hash) && payload["raw_excerpt"].present?
      payload = payload.merge("raw_excerpt" => "(see Activity Log row #{entry.id})")
    end

    {
      id: entry.id,
      event_type: entry.event_type,
      severity: entry.severity,
      title: entry.title,
      message: entry.message,
      subject_type: entry.subject_type,
      subject_id: entry.subject_id,
      subject_label: entry.subject_label,
      actor_user_id: entry.actor_user_id,
      payload: payload,
      # @lat: [[pipeline-activity-log-inspect-query#Query text per event type]]
      inspect_query: entry.inspect_query,
      created_at: entry.created_at.iso8601(6)
    }
  end

  class << self
    private

    def actor_email(actor)
      actor&.email&.to_s
    end

    def emit!(event_type, subject:, actor:, payload:, message:)
      title = TITLE_TEMPLATES.fetch(event_type).call(payload)
      severity = SEVERITY_FOR_EVENT.fetch(event_type)

      actor_user_id = case actor
      when User then actor.id
      when NilClass then nil
      else actor.try(:id)
      end

      ApplicationRecord.transaction do
        PipelineActivityLogEntry.create!(
          event_type: event_type,
          severity: severity,
          title: title,
          message: message,
          subject: subject,
          actor_user_id: actor_user_id,
          payload: payload
        )
      end

      # @lat: [[pipeline-activity-logger-overview#Why delivery is triggered by an after-create hook, not a hand-written dispatcher]]
    end
  end
end
