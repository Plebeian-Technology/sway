# frozen_string_literal: true

# @lat: [[legislation-pipeline#Runs, resume and restart]]
class LegislationPipelineRunService
  class StageAllowlistError < ArgumentError; end
  class LocaleError < ArgumentError; end
  class LocaleMismatchError < LocaleError; end
  class MissingLocaleError < LocaleError; end

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  class ResumeNotAllowed < StandardError
    def initialize(reason)
      super
    end
  end

  ALLOWED_PIPELINE_STAGES = LegislationPipelineRun::ALLOWED_PIPELINE_STAGES

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  # @lat: [[legislation-pipeline#How a stage resolves its SwayLocale]]
  def initialize(stages: nil, bill: nil, sway_locale: nil, download_missing_assets: nil)
    empty_stages = [] #: Array[String]
    @stages = stages.nil? ? empty_stages : Array(stages).map(&:to_s)
    @bill = bill

    if bill.present? && sway_locale.present? && bill.sway_locale_id.present? && bill.sway_locale_id != sway_locale.id
      raise LocaleMismatchError, "Single-bill pipeline run cannot override bill jurisdiction with a conflicting locale"
    end

    @sway_locale = sway_locale || bill&.sway_locale
    @download_missing_assets = download_missing_assets.nil? || download_missing_assets
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  def call(skip_enqueue: false)
    validate_stages!
    validate_locale!

    run = LegislationPipelineRun.create!(
      bill: @bill,
      sway_locale: @sway_locale,
      stages: @stages,
      download_missing_assets: @download_missing_assets,
      status: "queued",
      started_at: Time.current
    )

    RunLegislationPipelineJob.perform_later(run.id) unless skip_enqueue

    SwayLogging.info(
      "legislation_pipeline_run.created",
      run_id: run.id,
      bill_id: @bill&.id,
      sway_locale_id: @sway_locale&.id,
      stages: @stages,
      download_missing_assets: @download_missing_assets
    )

    run
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  def resume(parent_run, skip_enqueue: false)
    derived_kind = parent_run.bill_id.present? ? "single" : "all_bills"
    unless parent_run.status == "failed" && derived_kind == "single"
      raise ResumeNotAllowed,
        "Resume only allowed on failed kind='single' runs " \
        "(parent.status=#{parent_run.status.inspect}, kind=#{derived_kind.inspect})"
    end

    validate_stages_for!(parent_run.stages)

    sway_locale = parent_run.sway_locale || parent_run.bill&.sway_locale

    # @lat: [[legislation-pipeline#Runs, resume and restart]]
    new_run = LegislationPipelineRun.create!(
      bill: parent_run.bill,
      sway_locale: sway_locale,
      stages: parent_run.stages,
      download_missing_assets: parent_run.download_missing_assets,
      status: "queued",
      started_at: Time.current,
      parent_run_id: parent_run.id.to_s,
      origin: "resume"
    )

    # @lat: [[legislation-pipeline#Runs, resume and restart]]
    RunLegislationPipelineJob.perform_later(new_run.id, origin: "resume") unless skip_enqueue

    SwayLogging.info(
      "legislation_pipeline_run.resumed",
      new_run_id: new_run.id,
      parent_run_id: parent_run.id,
      sway_locale_id: new_run.sway_locale_id,
      download_missing_assets: new_run.download_missing_assets
    )

    new_run
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  # @lat: [[legislation-pipeline#Runs, resume and restart#Restart rejects indeterminate runs without a locale]]
  def restart(parent_run, download_missing_assets: nil, skip_enqueue: false)
    validate_stages_for!(parent_run.stages)

    sway_locale = parent_run.effective_sway_locale
    if sway_locale.nil?
      raise MissingLocaleError, "A SwayLocale is required for all-bills pipeline runs"
    end

    effective_dma =
      if download_missing_assets.nil?
        parent_run.download_missing_assets
      else
        download_missing_assets
      end

    new_run = LegislationPipelineRun.create!(
      bill: parent_run.bill,
      sway_locale: sway_locale,
      stages: parent_run.stages,
      download_missing_assets: effective_dma,
      status: "queued",
      started_at: Time.current,
      parent_run_id: parent_run.id.to_s,
      origin: "restart"
    )

    # @lat: [[legislation-pipeline#Runs, resume and restart]]
    RunLegislationPipelineJob.perform_later(new_run.id, origin: "restart") unless skip_enqueue

    SwayLogging.info(
      "legislation_pipeline_run.restarted",
      new_run_id: new_run.id,
      parent_run_id: parent_run.id,
      sway_locale_id: new_run.sway_locale_id,
      download_missing_assets: effective_dma
    )

    new_run
  end

  private

  def validate_locale!
    if @bill.nil? && @sway_locale.nil?
      raise MissingLocaleError, "A SwayLocale is required for all-bills pipeline runs"
    end
  end

  def validate_stages!
    validate_stages_for!(@stages)
  end

  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  def validate_stages_for!(stages)
    stages = Array(stages).map(&:to_s)
    raise StageAllowlistError, "At least one stage must be selected" if stages.empty?
    unknown = stages - ALLOWED_PIPELINE_STAGES
    if unknown.any?
      raise StageAllowlistError, "Unknown stages: #{unknown.inspect}"
    end
  end
end
