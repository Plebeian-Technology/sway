# frozen_string_literal: true

# @lat: [[activity-log-flash-transport#Why a test-only controller proves the round trip]]
class InertiaFlashProbeController < ApplicationController
  skip_before_action :verify_is_sway_admin, raise: false
  skip_before_action :authenticate_sway_user!, raise: false
  skip_before_action :is_api_request_and_is_route_api_accessible?, raise: false
  skip_before_action :set_sway_locale_id_in_session, raise: false

  def trigger
    run = LegislationPipelineRun.create!(remote_run_id: SecureRandom.uuid)
    PipelineActivityLogger.log_orphan_run_deleted!(run_id: run.id, actor: nil)
    render inertia: "ActivityLogFlashProbe", props: {ok: true}
  end

  # @lat: [[activity-log-flash-transport#Why the fallback is tested without a real overflow]]
  #
  # params[:bill_id] is required.
  def trigger_flash_error
    entry = PipelineActivityLogEntry.create!(
      event_type: "llm_json_parse_failure",
      severity: "error",
      title: "synthetic failure",
      message: "synthetic flash transport failure",
      payload: {raw_excerpt: "x" * 10}
    )
    flash[:activity_log_error] = {
      entry_id: entry.id,
      error_class: "SyntheticTestError"
    }
    redirect_to pipeline_bill_creator_path(id: params[:bill_id])
  end
end
