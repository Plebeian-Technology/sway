# frozen_string_literal: true

# == Schema Information
#
# Table name: legislation_pipeline_runs
# Database name: primary
#
#  id                      :integer          not null, primary key
#  completed_at            :datetime
#  current_stage           :string
#  download_missing_assets :boolean          default(TRUE), not null
#  error_message           :text
#  idempotency_key         :string           not null
#  origin                  :string           default("fresh"), not null
#  stages                  :text
#  started_at              :datetime
#  status                  :string           default("queued"), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#  bill_id                 :integer
#  parent_run_id           :string
#  remote_run_id           :string
#  sway_locale_id          :integer
#
# Indexes
#
#  index_legislation_pipeline_runs_on_bill_id          (bill_id)
#  index_legislation_pipeline_runs_on_idempotency_key  (idempotency_key) UNIQUE
#  index_legislation_pipeline_runs_on_parent_run_id    (parent_run_id)
#  index_legislation_pipeline_runs_on_remote_run_id    (remote_run_id) UNIQUE WHERE remote_run_id IS NOT NULL
#  index_legislation_pipeline_runs_on_status           (status)
#  index_legislation_pipeline_runs_on_sway_locale_id   (sway_locale_id)
#
# Foreign Keys
#
#  bill_id         (bill_id => bills.id)
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#
# @lat: [[legislation-pipeline#Runs, resume and restart]]
class LegislationPipelineRun < ApplicationRecord
  belongs_to :bill, optional: true
  belongs_to :sway_locale, optional: true

  # @lat: [[legislation-pipeline#How a stage resolves its SwayLocale]]
  def effective_sway_locale
    sway_locale || bill&.sway_locale
  end

  # @lat: [[resume-stage-history-walk#Why parent_run_id points backward at all]]
  belongs_to :parent_run,
    class_name: "LegislationPipelineRun",
    optional: true

  has_many :child_runs,
    class_name: "LegislationPipelineRun",
    foreign_key: :parent_run_id,
    inverse_of: :parent_run,
    dependent: :nullify

  # @lat: [[legislation-pipeline-run-bills-wire-shape#Why the association and the batch iterator both pin a stable order]]
  has_many :legislation_pipeline_run_bills, -> { order(:sort_order) }, class_name: "PipelineRunBill", foreign_key: :legislation_pipeline_run_id, dependent: :destroy, inverse_of: :legislation_pipeline_run
  has_many :pipeline_run_bills, -> { order(:sort_order) }, class_name: "PipelineRunBill", foreign_key: :legislation_pipeline_run_id, dependent: :destroy, inverse_of: :legislation_pipeline_run

  has_many :legislation_pipeline_run_stages, class_name: "PipelineRunStage", dependent: :destroy, inverse_of: :legislation_pipeline_run
  has_many :pipeline_run_stages, class_name: "PipelineRunStage", dependent: :destroy, inverse_of: :legislation_pipeline_run

  # @lat: [[llm-summaries#Batch summarisation#Why chunking is a progress decision, not a cost one]]
  has_many :legislation_pipeline_run_summary_batches, class_name: "PipelineRunSummaryBatch", dependent: :destroy, inverse_of: :legislation_pipeline_run
  has_many :pipeline_run_summary_batches, class_name: "PipelineRunSummaryBatch", dependent: :destroy, inverse_of: :legislation_pipeline_run

  # @lat: [[legislation-pipeline-run-bills-wire-shape#Why the association and the batch iterator both pin a stable order]]
  def each_pipeline_run_bill(&block)
    pipeline_run_bills.unscope(:order).find_each(cursor: [:sort_order, :id], &block)
  end

  # @lat: [[rbs-signatures#Why a serialized column's generated signature is wrong]]
  serialize :stages, coder: JSON

  # @lat: [[legislation-pipeline-run-remote-run-id-history#Why the guard against overwriting stays]]
  before_validation :assign_remote_run_id, on: :create
  before_create :assign_idempotency_key

  # @lat: [[legislation-pipeline-stage-list-naming-and-order#Why fetch-law runs second]]
  ALLOWED_PIPELINE_STAGES = %w[
    fetch-bills
    fetch-law
    extract-text
    parse-sections
    generate-diffs
    fetch-hearings
    clean-testimony
    summarize-bill
  ].freeze

  # @lat: [[legislation-pipeline-run-state-machine-design#Why TERMINAL_SUCCESS_STATUSES lists both completed and succeeded]]
  TERMINAL_SUCCESS_STATUSES = %w[completed succeeded].freeze

  # @lat: [[legislation-pipeline-run-state-machine-design#Why the per-stage X-ing states never appear in TERMINAL_SUCCESS_STATUSES]]
  PHASE_52_STAGE_STATES = %i[
    fetching_bills
    fetching_law
    extracting_text
    parsing_sections
    generating_diffs
    fetching_hearings
    cleaning_testimony
    summarizing
    awaiting_summary_batch
  ].freeze

  PHASE_52_NON_TERMINAL_STATES = ([:queued, :running] + PHASE_52_STAGE_STATES).freeze

  # @lat: [[legislation-pipeline-fail-fast-integrity-checks#LegislationPipelineRun::STAGE_STATUS_TO_DAG_NAME]]
  STAGE_STATUS_TO_DAG_NAME = {
    "fetching_bills" => "fetch_bills",
    "fetching_law" => "fetch_law",
    "extracting_text" => "extract_text",
    "parsing_sections" => "parse_sections",
    "generating_diffs" => "generate_diffs",
    "fetching_hearings" => "fetch_hearings",
    "cleaning_testimony" => "clean_testimony",
    "summarizing" => "summarize",
    "awaiting_summary_batch" => "summarize"
  }.freeze

  # @lat: [[legislation-pipeline-fail-fast-integrity-checks#LegislationPipelineRun::STAGE_STATUS_TO_DAG_NAME]]
  PHASE_52_STAGE_STATES.each do |state|
    unless STAGE_STATUS_TO_DAG_NAME.key?(state.to_s)
      raise "LegislationPipelineRun::STAGE_STATUS_TO_DAG_NAME missing entry for #{state.inspect}"
    end
  end

  # @lat: [[legislation-pipeline-run-state-machine-design#Why the initial state is :queued, not nil]]
  state_machine :status, initial: :queued do
    state :fetching_bills
    state :extracting_text
    state :parsing_sections
    state :generating_diffs
    state :fetching_law
    state :fetching_hearings
    state :cleaning_testimony
    state :summarizing
    state :awaiting_summary_batch

    event :start_running do
      transition queued: :running
    end

    event :mark_completed do
      transition running: :completed
    end

    event :mark_failed do
      transition queued: :failed
      transition running: :failed
    end

    # @lat: [[legislation-pipeline-run-state-machine-design#Why mark_cancelled reaches every per-stage state]]
    event :mark_cancelled do
      transition PHASE_52_NON_TERMINAL_STATES => :cancelled
    end

    # @lat: [[legislation-pipeline-run-state-machine-design#Why TERMINAL_SUCCESS_STATUSES lists both completed and succeeded]]
    event :mark_succeeded do
      transition running: :succeeded
    end

    event :mark_partial do
      transition running: :partial
    end

    event :start_fetch_bills do
      transition running: :fetching_bills
    end
    event :complete_fetch_bills do
      transition fetching_bills: :running
    end

    event :start_extract_text do
      transition running: :extracting_text
    end
    event :complete_extract_text do
      transition extracting_text: :running
    end

    event :start_parse_sections do
      transition running: :parsing_sections
    end
    event :complete_parse_sections do
      transition parsing_sections: :running
    end

    event :start_generate_diffs do
      transition running: :generating_diffs
    end
    event :complete_generate_diffs do
      transition generating_diffs: :running
    end

    event :start_fetch_law do
      transition running: :fetching_law
    end
    event :complete_fetch_law do
      transition fetching_law: :running
    end

    event :start_fetch_hearings do
      transition running: :fetching_hearings
    end
    event :complete_fetch_hearings do
      transition fetching_hearings: :running
    end

    event :start_clean_testimony do
      transition running: :cleaning_testimony
    end
    event :complete_clean_testimony do
      transition cleaning_testimony: :running
    end

    event :start_summarize do
      transition running: :summarizing
    end
    event :complete_summarize do
      transition summarizing: :running
    end

    # @lat: [[llm-summaries#Batch summarisation#Why the waiting state loops back to summarizing]]
    event :await_summary_batch do
      transition summarizing: :awaiting_summary_batch
    end
    event :resume_summary_batch do
      transition awaiting_summary_batch: :summarizing
    end

    event :force_fail do
      transition PHASE_52_NON_TERMINAL_STATES => :failed
    end

    # @lat: [[legislation-pipeline-run-current-stage#Behavior on terminal statuses]]
    before_transition any => any do |run, transition|
      dag_name = STAGE_STATUS_TO_DAG_NAME[transition.to.to_s]
      run.current_stage = dag_name if dag_name

      # @lat: [[legislation-pipeline-run-current-stage#Why completed_at is stamped in the same hook]]
      run.completed_at = Time.current if TERMINAL_STATUSES.include?(transition.to.to_sym) && run.completed_at.nil?
    end

    # @lat: [[pipeline-activity-log-auto-included-stage-context#LegislationPipelineRun's audit-log transaction guarantee]]
    after_transition any => any do |run, transition|
      # @lat: [[pipeline-activity-log-auto-included-stage-context#LegislationPipelineRun's audit-log transaction guarantee]]
      next if transition.from.nil?

      # @lat: [[pipeline-activity-log-auto-included-stage-context#LegislationPipelineRun's audit-log transaction guarantee]]
      run.send(:sync_pipeline_run_stage, transition)

      PipelineActivityLogger.emit_state_transition!(
        run: run,
        from: transition.from,
        to: transition.to,
        event: transition.event
      )
    end
  end

  # @lat: [[legislation-pipeline-run-state-machine-design#Why TERMINAL_STATUSES is computed by subtraction]]
  TERMINAL_STATUSES = (state_machine(:status).states.map(&:name).compact - PHASE_52_NON_TERMINAL_STATES).freeze

  # @lat: [[legislation-pipeline-run-broadcast-status-change#Why the after_commit hook is separate and gated on saved_change_to_status?]]
  after_commit on: :update do
    if saved_change_to_status?
      from, to = saved_change_to_status
      broadcast_status_change(from: from, to: to)
    end
  end

  # @lat: [[legislation-pipeline-run-broadcast-status-change#Why PipelineRunBroadcast.deliver never lets a failure propagate]]
  def broadcast_status_change(from:, to:)
    PipelineRunBroadcast.deliver(
      remote_run_id || "global",
      {
        scope: "run",
        run_id: id,
        status: status,
        current_stage: current_stage,
        error_message: error_message,
        event: nil,
        from: from,
        to: to
      },
      log_event: "legislation_pipeline_run.status_broadcast_failed",
      run_id: id,
      from: from,
      to: to
    )
  end

  # @lat: [[legislation-pipeline-reopen-stuck-stage#What it has to do by hand]]
  def reopen_stuck_stage!
    previous_status = status.to_s
    return false unless PHASE_52_STAGE_STATES.map(&:to_s).include?(previous_status)

    update_columns(status: "running")
    PipelineActivityLogger.emit_state_transition!(
      run: self,
      from: previous_status,
      to: "running",
      event: "reopen_stuck_stage"
    )
    broadcast_status_change(from: previous_status, to: "running")
    true
  end

  # @lat: [[bill-pipeline-refresh-active-statuses-drift#Why ACTIVE_STATUSES must include the per-stage states]]
  ACTIVE_STATUSES = (%w[queued running] + PHASE_52_STAGE_STATES.map(&:to_s)).freeze

  scope :active_global, -> { where(bill_id: nil, status: ACTIVE_STATUSES) }
  scope :active_for_bill, ->(bill) { where(bill_id: bill.id, status: ACTIVE_STATUSES) }
  # @lat: [[bill-pipeline-refresh-active-statuses-drift#Why active_any exists alongside active_global]]
  scope :cleaning_testimony_for, ->(bill) { where(status: "cleaning_testimony", bill_id: [bill.id, nil]) }
  scope :active_any, -> { where(status: ACTIVE_STATUSES) }

  # @lat: [[legislation-pipeline-run-orphan-detection#The Solid Queue job lookup]]
  ORPHAN_AGE_THRESHOLD = 4.hours

  scope :orphan_age_candidates, -> {
    where(status: %w[queued running]).where("created_at < ?", ORPHAN_AGE_THRESHOLD.ago)
  }

  # @lat: [[legislation-pipeline-run-orphan-detection#The Solid Queue job lookup]]
  def orphan?
    return false unless %w[queued running].include?(status)
    return false unless created_at < ORPHAN_AGE_THRESHOLD.ago
    !self.class.solid_queue_job_exists_for?(self)
  end

  # @lat: [[legislation-pipeline-run-orphan-detection#Abandoned runs: a second, separate check]]
  ABANDONED_AFTER = 4.hours

  # @lat: [[llm-summaries#Batch summarisation#Why chunking is a progress decision, not a cost one]]
  scope :awaiting_live_summary_batch, -> {
    where(status: "awaiting_summary_batch")
      .where(id: PipelineRunSummaryBatch.live.select(:legislation_pipeline_run_id))
  }

  # @lat: [[llm-summaries#Batch summarisation#Which runs the sweep can reach]]
  scope :with_pending_summary_batches, -> {
    where(status: "awaiting_summary_batch").or(
      where.not(status: PHASE_52_NON_TERMINAL_STATES.map(&:to_s))
        .where(id: PipelineRunSummaryBatch.pending_ingest.select(:legislation_pipeline_run_id))
    )
  }

  # @lat: [[legislation-pipeline-run-orphan-detection#Abandoned runs: a second, separate check]]
  # @lat: [[llm-summaries#Batch summarisation#Why no job waits on a batch]]
  scope :abandoned_candidates, -> {
    where(status: PHASE_52_NON_TERMINAL_STATES.map(&:to_s))
      .where(updated_at: ..ABANDONED_AFTER.ago)
      .where.not(id: awaiting_live_summary_batch.select(:id))
  }

  # @lat: [[legislation-pipeline-run-orphan-detection#Abandoned runs: a second, separate check]]
  def abandoned?
    return false unless PHASE_52_NON_TERMINAL_STATES.map(&:to_s).include?(status)
    return false if updated_at > ABANDONED_AFTER.ago
    return false if summary_batch_awaited?
    !self.class.solid_queue_job_exists_for?(self)
  end

  # @lat: [[llm-summaries#Batch summarisation#Why resume draws the same line as abandonment]]
  def summary_batch_awaited?
    return false unless status == "awaiting_summary_batch"

    live_summary_batches.any?
  end

  # @lat: [[llm-summaries#Batch summarisation#Why chunking is a progress decision, not a cost one]]
  def live_summary_batches
    pipeline_run_summary_batches.to_a.select(&:live?)
  end

  # @lat: [[llm-summaries#Batch summarisation#A batch is read back exactly once]]
  def pending_summary_batches
    pipeline_run_summary_batches.to_a.reject(&:ingested?)
  end

  # @lat: [[legislation-pipeline-run-orphan-detection#The Solid Queue job lookup]]
  def self.solid_queue_job_exists_for?(run)
    SolidQueue::Job
      .where(class_name: "RunLegislationPipelineJob")
      .where(finished_at: nil)
      .where("json_extract(arguments, '$.arguments[0]') = ?", run.id)
      .exists?
  rescue => e
    SwayLogging.warn("orphan_lookup_failed: #{e.class}: #{e.message}")
    # @lat: [[legislation-pipeline-run-orphan-detection#The Solid Queue job lookup]]
    true
  end

  def to_builder
    Jbuilder.new do |p|
      p.id id
      # @lat: [[legislation-pipeline-run-remote-run-id-history#The fix]]
      p.remote_run_id remote_run_id
      p.status status
      p.current_stage current_stage
      p.error_message error_message
      p.bill_id bill_id
      p.bill_external_id bill&.external_id
      p.sway_locale_id sway_locale_id
      p.stages stages
      p.download_missing_assets download_missing_assets
      # @lat: [[legislation-pipeline-run-stage-timing-wire-shape#pipeline-run-stage-timing]]
      p.started_at started_at&.utc&.iso8601
      p.completed_at completed_at&.utc&.iso8601
      # @lat: [[legislation-pipeline-run-orphan-detection#Abandoned runs: a second, separate check]]
      p.abandoned abandoned?

      # @lat: [[llm-summaries#Batch summarisation#What the operator sees while a batch is outstanding]]
      p.summary_batch summary_batch_progress

      # @lat: [[resume-stage-history-walk#The rest of the audit trail in to_builder]]
      p.parent_run_id parent_run_id
      p.origin origin
      p.kind(bill_id.present? ? "single" : "all_bills")
      p.pipeline_run_stages pipeline_run_stages.each_with_index.map { |s, i|
        {
          stage_name: s.stage_name,
          status: s.status,
          position: i + 1,
          output_summary: s.output_summary,
          # @lat: [[legislation-pipeline-run-stage-timing-wire-shape#pipeline-run-stage-timing]]
          started_at: s.started_at&.utc&.iso8601,
          finished_at: s.finished_at&.utc&.iso8601
        }
      }

      # @lat: [[legislation-pipeline-run-bills-wire-shape#Avoiding N+1 queries]]
      p.pipeline_run_bills(
        if bill_id.present?
          nil
        else
          loaded_bills = pipeline_run_bills.to_a
          external_ids = loaded_bills.map(&:bill_external_id)
          # @lat: [[legislation-pipeline-external-id-ambiguity#LegislationPipelineRun.to_builder's title lookup]]
          title_map = Legislation::PipelineBillLookup.title_map(external_ids)
          loaded_bills.map do |prb|
            {
              bill_external_id: prb.bill_external_id,
              title: title_map[prb.bill_external_id]&.truncate(80),
              status: prb.status,
              # @lat: [[legislation-pipeline-run-stage-timing-wire-shape#pipeline-run-bills-timing]]
              started_at: prb.started_at&.utc&.iso8601,
              finished_at: prb.finished_at&.utc&.iso8601,
              error_message: prb.error_message,
              sort_order: prb.sort_order
            }
          end
        end
      )
    end
  end

  private

  # @lat: [[llm-summaries#Batch summarisation#What the operator sees while a batch is outstanding]]
  def summary_batch_progress
    batches = pipeline_run_summary_batches.to_a
    return nil if batches.empty?

    submitted_ats = batches.filter_map(&:submitted_at)
    expiries = batches.filter_map(&:expires_at)

    {
      awaiting: status == "awaiting_summary_batch",
      batches_total: batches.size,
      batches_ingested: batches.count(&:ingested?),
      items_total: batches.sum(&:item_count),
      items_succeeded: batches.sum(&:succeeded_count),
      items_failed: batches.sum(&:failed_count),
      first_submitted_at: submitted_ats.min&.utc&.iso8601,
      expires_at: expiries.max&.utc&.iso8601
    }
  end

  # @lat: [[legislation-pipeline-run-remote-run-id-history#Why the guard against overwriting stays]]
  def assign_idempotency_key
    self.idempotency_key = SecureRandom.uuid if idempotency_key.blank?
  end

  # @lat: [[legislation-pipeline-run-remote-run-id-history#Why the guard against overwriting stays]]
  def assign_remote_run_id
    self.remote_run_id = SecureRandom.uuid if remote_run_id.blank?
  end

  # @lat: [[pipeline-activity-log-auto-included-stage-context#LegislationPipelineRun's audit-log transaction guarantee]]
  def sync_pipeline_run_stage(transition)
    to_dag = STAGE_STATUS_TO_DAG_NAME[transition.to.to_s] #: String?
    from_dag = STAGE_STATUS_TO_DAG_NAME[transition.from.to_s] #: String?

    if to_dag
      stage = pipeline_run_stages.find_or_initialize_by(stage_name: to_dag)
      stage.started_at ||= Time.current
      stage.save! if stage.new_record? || stage.changed?
      stage.start_running! if stage.can_start_running?
    elsif from_dag && transition.to.to_s == "running"
      stage = pipeline_run_stages.find_by(stage_name: from_dag)
      if stage
        stage.finished_at ||= Time.current
        stage.save! if stage.changed?
        stage.mark_succeeded! if stage.can_mark_succeeded?
      end
    elsif from_dag && (transition.to.to_s == "failed" || transition.to.to_s == "cancelled")
      # @lat: [[legislation-pipeline-mark-cancelled-stage-sync#Why cancelling from the plain :running state must not create or touch any stage row]]
      stage = pipeline_run_stages.find_by(stage_name: from_dag)
      if stage
        stage.finished_at ||= Time.current
        stage.save! if stage.changed?
        stage.mark_failed! if stage.can_mark_failed?
      end
    end
  end
end
