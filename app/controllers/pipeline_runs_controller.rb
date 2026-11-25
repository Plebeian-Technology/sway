# frozen_string_literal: true

# @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The admin surface is index-only]]
class PipelineRunsController < ApplicationController
  before_action :verify_is_sway_admin

  def index
    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The admin surface is index-only]]
    scope = LegislationPipelineRun.order(created_at: :desc).limit(50)
    render_inertia_or_json(
      page: Pages::ADMIN_PIPELINE_RUNS,
      props: {
        runs: ::PipelineRuns::RunSummarySerializer.call(scope)
      }
    )
  end

  def force_fail
    run = LegislationPipelineRun.find(params[:id])
    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The admin surface is index-only#Force-fail returns to the working surface]]
    back_path = if run.bill_id
      pipeline_bill_creator_path(id: run.bill_id)
    elsif params[:back_to].presence == "bill_creator"
      new_bill_creator_path(bill_creator_tab: :pipeline)
    else
      pipeline_runs_path
    end

    unless run.can_force_fail?
      return respond_after_write(
        back_path,
        errors: {pipeline: "Run ##{run.id} is not in-flight (status: #{run.status})"}
      )
    end

    confirm = params[:confirm_phrase].to_s.strip
    unless confirm == "force fail"
      return respond_after_write(back_path, errors: {pipeline: "Confirmation phrase mismatch"})
    end

    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The admin surface is index-only#Force-fail records its reason before transition]]
    run.update!(error_message: "Force-failed by admin user #{current_user.id}")
    run.force_fail!
    PipelineActivityLogger.log_force_fail_triggered!(run: run, actor: current_user)
    respond_after_write(back_path, notice: "Run ##{run.id} force-failed", json: force_failed_run_json(run))
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The admin surface is index-only]]
  def destroy_orphans
    deleted_ids = [] #: Array[Integer]
    LegislationPipelineRun.orphan_age_candidates.find_each do |run|
      next unless run.orphan?
      run_id = run.id
      run.destroy!
      PipelineActivityLogger.log_orphan_run_deleted!(run_id: run_id, actor: current_user)
      deleted_ids << run_id
    end

    if mobile_api_request?
      render json: {deleted_ids: deleted_ids, count: deleted_ids.length}, status: :ok
    else
      message =
        if deleted_ids.empty?
          "No orphan runs to remove."
        else
          "Removed #{deleted_ids.length} orphan run#{"s" unless deleted_ids.length == 1} (#{deleted_ids.join(", ")})."
        end
      flash[:notice] = message
      back_path = (params[:back_to].presence == "bill_creator") ? new_bill_creator_path(bill_creator_tab: :pipeline) : pipeline_runs_path
      redirect_to back_path
    end
  end

  private

  # @lat: [[mobile-bill-creator#Sections#The pipeline cleanup section]]
  def force_failed_run_json(run)
    return {} unless mobile_api_request?

    {run: PipelineRuns::RunSummarySerializer.serialize(run)}
  end

  # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#The admin surface is index-only#The orphan lookup wrapper remains test-visible]]
  def solid_queue_job_exists_for?(run)
    LegislationPipelineRun.solid_queue_job_exists_for?(run)
  end
end
