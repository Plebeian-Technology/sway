# frozen_string_literal: true

# == Schema Information
#
# Table name: pipeline_activity_log_entries
# Database name: primary
#
#  id            :integer          not null, primary key
#  event_type    :string           not null
#  message       :string           not null
#  payload       :text             default({}), not null
#  severity      :string           not null
#  subject_type  :string
#  title         :string           not null
#  created_at    :datetime         not null
#  actor_user_id :integer
#  subject_id    :string
#
# Indexes
#
#  index_activity_log_entries_on_created_at_desc         (created_at DESC)
#  index_activity_log_entries_on_subject_polymorphic     (subject_type,subject_id)
#  index_activity_log_severity_and_created_at            (severity,created_at DESC)
#  index_pipeline_activity_log_entries_on_actor_user_id  (actor_user_id)
#  index_pipeline_activity_log_entries_on_event_type     (event_type)
#
# Foreign Keys
#
#  actor_user_id  (actor_user_id => users.id)
#
class PipelineActivityLogEntry < ApplicationRecord
  # @lat: [[pipeline-activity-log-event-types-curation#Two were duplicate spellings of real events]]
  EVENT_TYPES = %w[
    stage_failed ingestion_failure llm_provider_error
    llm_json_parse_failure summary_regenerate_triggered
    state_transition bill_state_transition
    paste_summary_accepted paste_summary_rejected
    org_position_decision orphan_run_deleted force_fail_triggered
    stage_budget_tripped
    summary_stood_down_for_paste summary_skipped_no_source_text
    resume_deferred_for_summary_batch
    attachment_download_attempt
  ].freeze

  # @lat: [[pipeline-activity-logger-overview#What PipelineActivityLogger does]]
  SEVERITIES = %w[info warning error].freeze

  belongs_to :subject, polymorphic: true, optional: true
  belongs_to :actor_user, class_name: "User", optional: true

  serialize :payload, coder: JSON

  validates :event_type, presence: true, inclusion: {in: EVENT_TYPES}
  validates :severity, presence: true, inclusion: {in: SEVERITIES}
  validates :title, presence: true, length: {maximum: 60}
  validates :message, presence: true

  # @lat: [[pipeline-activity-logger-overview#How PipelineActivityLogEntry triggers delivery]]
  after_commit :dispatch_pipeline_activity_transport, on: :create

  def readonly?
    persisted?
  end

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }
  scope :for_subject, ->(type, id) { where(subject_type: type, subject_id: id) }
  scope :errors_only, -> { where(severity: "error") }
  scope :since, ->(time) { where("created_at >= ?", time) }

  def subject_label
    case subject_type
    when "Bill" then subject&.external_id
    when "LegislationPipelineRun" then "Run #{subject&.remote_run_id.to_s[0..7]}"
    when "Stage" then subject_id
    end
  end

  # @lat: [[pipeline-activity-log-inspect-query#Query text per event type]]
  def inspect_query
    # @lat: [[rbs-signatures#RBS signatures#Why a guard against an impossible shape means the type is wrong]]
    raw_payload = payload #: untyped
    # @type var p: Hash[String, untyped]
    p = raw_payload.is_a?(Hash) ? raw_payload.deep_stringify_keys : {}

    case event_type
    when "org_position_decision"
      bill_id = p["bill_id"].to_i
      org_name = p["org_name"].to_s
      "OrganizationBillPosition.joins(:organization).where(bill_id: #{bill_id}, organizations: {name: #{org_name.inspect}})"
    when "paste_summary_accepted", "paste_summary_rejected"
      bill_id = p["bill_id"].to_i
      "BillLlmProvisioning.where(bill_id: #{bill_id}).order(updated_at: :desc).first"
    when "force_fail_triggered", "state_transition", "resume_deferred_for_summary_batch"
      run_id = p["run_id"].to_i
      "LegislationPipelineRun.find(#{run_id})"
    when "orphan_run_deleted"
      run_id = p["run_id"].to_i
      "LegislationPipelineRun.where(id: #{run_id}) # destroyed — check pipeline_activity_log_entries for history"
    when "bill_state_transition"
      bill_run_id = p["bill_run_id"].to_i
      "PipelineRunBill.find(#{bill_run_id})"
    else
      "PipelineActivityLogEntry.find(#{id})"
    end
  end

  private

  # @lat: [[pipeline-activity-logger-overview#How PipelineActivityLogEntry triggers delivery]]
  def dispatch_pipeline_activity_transport
    PipelineActivityLogger::Transport.dispatch(self)
  rescue => e
    SwayLogging.warn(
      "[PipelineActivityLogEntry] after_commit transport failed for entry ##{id} " \
      "(event_type=#{event_type.inspect}, subject=#{subject_type}##{subject_id}): " \
      "#{e.class} #{e.message}"
    )
  end
end
