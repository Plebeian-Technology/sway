# frozen_string_literal: true

# @lat: [[legislation-pipeline-run-sourcing-concern#Why legislation_pipeline_run_props reads active_any, not active_global]]
module LegislationPipelineRunSourcing
  extend ActiveSupport::Concern

  RECENT_PIPELINE_RUNS_LIMIT = 20

  included do
    inertia_share do
      # @lat: [[legislation-pipeline-run-sourcing-concern#Why legislation_pipeline_run_props reads active_any, not active_global]]
      next({}) unless current_user&.is_sway_admin?
      legislation_pipeline_run_props
    end
  end

  private

  # @lat: [[legislation-pipeline-run-sourcing-concern#Why legislation_pipeline_run_props reads active_any, not active_global]]
  # @lat: [[pipeline-run-pin-vs-active-run#Why the pinned run and the active run are two different props]]
  def legislation_pipeline_run_props
    {
      legislation_pipeline_run: -> { pipeline_share_snapshot[:legislation_pipeline_run] },
      recent_pipeline_runs: -> { pipeline_share_snapshot[:recent_pipeline_runs] },
      stale_pipeline_run_count: -> { pipeline_share_snapshot[:stale_pipeline_run_count] },
      orphan_pipeline_run_count: -> { pipeline_share_snapshot[:orphan_pipeline_run_count] },
      active_legislation_pipeline_run: -> { pipeline_share_snapshot[:active_legislation_pipeline_run] }
    }
  end

  # @lat: [[legislation-pipeline-run-sourcing-concern#Why legislation_pipeline_run_props reads active_any, not active_global]]
  def pipeline_share_snapshot
    @pipeline_share_snapshot ||= compute_pipeline_share_snapshot
  end

  def compute_pipeline_share_snapshot
    # @lat: [[legislation-pipeline-run-sourcing-concern#Why legislation_pipeline_run_props reads active_any, not active_global]]
    active_runs = LegislationPipelineRun
      .active_any
      .includes(:pipeline_run_bills, :pipeline_run_stages, :pipeline_run_summary_batches)
      .order(created_at: :desc)
      .to_a

    surfaced_run = surfaced_pipeline_run(active_runs)

    # @lat: [[legislation-pipeline#The legislation pipeline#Runs, resume and restart#Stuck runs require evidence of abandonment]]
    abandoned_candidates = LegislationPipelineRun.abandoned_candidates.includes(:pipeline_run_summary_batches).to_a
    candidates = LegislationPipelineRun.orphan_age_candidates.to_a
    {
      legislation_pipeline_run: surfaced_run&.to_builder&.attributes!,
      recent_pipeline_runs: recent_pipeline_runs_summary,
      stale_pipeline_run_count: abandoned_candidates.count(&:abandoned?),
      orphan_pipeline_run_count: candidates.count(&:orphan?),
      # @lat: [[pipeline-run-pin-vs-active-run#Why the pinned run and the active run are two different props]]
      active_legislation_pipeline_run: active_runs.first&.to_builder&.attributes!
    }
  end

  # @lat: [[legislation-pipeline-run-sourcing-concern#Why surfaced_pipeline_run falls back to successful runs]]
  def surfaced_pipeline_run(active_runs)
    explicit = explicitly_selected_pipeline_run
    return explicit if explicit

    active_runs.first ||
      LegislationPipelineRun
        .includes(:pipeline_run_bills, :pipeline_run_stages, :pipeline_run_summary_batches)
        .order(created_at: :desc, id: :desc)
        .first
  end

  def explicitly_selected_pipeline_run
    run_id = params[:run_id].presence
    return nil unless run_id

    LegislationPipelineRun
      .includes(:pipeline_run_bills, :pipeline_run_stages, :pipeline_run_summary_batches)
      .find_by(id: run_id)
  end

  # @lat: [[legislation-pipeline-run-sourcing-concern#Why recent_pipeline_runs_summary eager-loads bills]]
  def recent_pipeline_runs_summary
    LegislationPipelineRun
      .includes(:bill)
      .order(created_at: :desc, id: :desc)
      .limit(RECENT_PIPELINE_RUNS_LIMIT)
      .map do |run|
        {
          id: run.id,
          status: run.status,
          kind: run.bill_id.present? ? "single" : "all_bills",
          bill_external_id: run.bill&.external_id,
          # @lat: [[legislation-pipeline-run-stage-timing-wire-shape#recent-runs-row]]
          created_at: run.created_at&.utc&.iso8601,
          completed_at: run.completed_at&.utc&.iso8601
        }
      end
  end
end
