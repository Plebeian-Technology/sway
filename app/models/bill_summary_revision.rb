# frozen_string_literal: true

# @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
# == Schema Information
#
# Table name: bill_summary_revisions
# Database name: primary
#
#  id                      :integer          not null, primary key
#  llm_model               :string
#  llm_provider            :string
#  origin                  :string           not null
#  publication_role        :string           not null
#  review_state            :string           not null
#  summary_markdown        :text             not null
#  created_at              :datetime         not null
#  actor_id                :integer
#  bill_id                 :integer          not null
#  news_source_snapshot_id :integer
#  restored_from_id        :integer
#
# Indexes
#
#  index_bill_summary_revisions_on_actor_id                 (actor_id)
#  index_bill_summary_revisions_on_bill_id                  (bill_id)
#  index_bill_summary_revisions_on_bill_id_and_created_at   (bill_id,created_at)
#  index_bill_summary_revisions_on_news_source_snapshot_id  (news_source_snapshot_id)
#  index_bill_summary_revisions_on_restored_from_id         (restored_from_id)
#
# Foreign Keys
#
#  actor_id                 (actor_id => users.id)
#  bill_id                  (bill_id => bills.id)
#  news_source_snapshot_id  (news_source_snapshot_id => news_article_source_snapshots.id) ON DELETE => nullify
#  restored_from_id         (restored_from_id => bill_summary_revisions.id)
#
class BillSummaryRevision < ApplicationRecord
  ORIGINS = %w[
    model_generation
    operator_edit
    operator_paste
    restoration
    initial_baseline
  ].freeze

  PUBLICATION_ROLES = %w[published draft].freeze
  REVIEW_STATES = %w[unreviewed reviewed unknown].freeze

  belongs_to :bill
  belongs_to :actor, class_name: "User", optional: true
  belongs_to :restored_from, class_name: "BillSummaryRevision", optional: true
  belongs_to :news_source_snapshot, class_name: "NewsArticleSourceSnapshot", optional: true

  validates :summary_markdown, presence: true
  validates :origin, presence: true, inclusion: {in: ORIGINS}
  validates :publication_role, presence: true, inclusion: {in: PUBLICATION_ROLES}
  validates :review_state, presence: true, inclusion: {in: REVIEW_STATES}
  validate :restored_from_belongs_to_same_bill, if: -> { restored_from_id.present? }
  validate :news_source_snapshot_belongs_to_same_bill, if: -> { news_source_snapshot_id.present? }

  before_validation :capture_initial_baseline, on: :create
  before_update :prevent_mutation
  before_destroy :prevent_mutation

  def readonly?
    persisted?
  end

  def actor_name
    actor&.full_name.presence || actor&.email.presence
  end

  def initial_baseline?
    origin == "initial_baseline"
  end

  def self.ensure_baseline!(bill, provisioning: nil)
    return if bill.nil? || bill.bill_summary_revisions.exists?

    provisioning ||= bill.bill_llm_provisioning

    bill.with_lock do
      return if bill.bill_summary_revisions.exists?

      has_public = bill.summary.present? && bill.summary.to_s.strip != Bill::SUMMARY_PLACEHOLDER
      has_draft = provisioning.present? && provisioning.llm_summary.present?

      if has_public && has_draft && bill.summary != provisioning.llm_summary
        create!(
          bill: bill,
          summary_markdown: bill.summary,
          origin: "initial_baseline",
          publication_role: "published",
          review_state: "unknown",
          actor: nil,
          created_at: bill.updated_at || Time.current
        )

        draft_origin = (provisioning.llm_provider == BillLlmProvisioning::OPERATOR_PASTE_PROVIDER) ? "operator_paste" : "model_generation"
        draft_review = (provisioning.llm_provider == BillLlmProvisioning::OPERATOR_PASTE_PROVIDER) ? "unknown" : "unreviewed"

        create!(
          bill: bill,
          summary_markdown: provisioning.llm_summary,
          origin: draft_origin,
          publication_role: "draft",
          review_state: draft_review,
          actor: nil,
          llm_provider: provisioning.llm_provider,
          llm_model: provisioning.llm_model,
          created_at: provisioning.llm_generated_at || provisioning.updated_at || bill.updated_at || Time.current
        )
      elsif has_public
        create!(
          bill: bill,
          summary_markdown: bill.summary,
          origin: "initial_baseline",
          publication_role: "published",
          review_state: "unknown",
          actor: nil,
          llm_provider: (has_draft && bill.summary == provisioning.llm_summary) ? provisioning.llm_provider : nil,
          llm_model: (has_draft && bill.summary == provisioning.llm_summary) ? provisioning.llm_model : nil,
          created_at: (has_draft && bill.summary == provisioning.llm_summary && provisioning.llm_generated_at) ? provisioning.llm_generated_at : (bill.updated_at || Time.current)
        )
      elsif has_draft
        draft_origin = (provisioning.llm_provider == BillLlmProvisioning::OPERATOR_PASTE_PROVIDER) ? "operator_paste" : "model_generation"
        draft_review = (provisioning.llm_provider == BillLlmProvisioning::OPERATOR_PASTE_PROVIDER) ? "unknown" : "unreviewed"

        create!(
          bill: bill,
          summary_markdown: provisioning.llm_summary,
          origin: draft_origin,
          publication_role: "draft",
          review_state: draft_review,
          actor: nil,
          llm_provider: provisioning.llm_provider,
          llm_model: provisioning.llm_model,
          created_at: provisioning.llm_generated_at || provisioning.updated_at || bill.updated_at || Time.current
        )
      end
    end
  end

  def self.record_revision!(
    bill:,
    summary_markdown:,
    origin:,
    publication_role:,
    review_state:,
    actor: nil,
    llm_provider: nil,
    llm_model: nil,
    restored_from: nil,
    created_at: nil,
    news_source_snapshot: nil
  )
    return nil if bill.nil? || summary_markdown.blank?

    snapshot_id = news_source_snapshot.is_a?(NewsArticleSourceSnapshot) ? news_source_snapshot.id : news_source_snapshot

    bill.with_lock do
      if origin.to_s != "initial_baseline" && bill.bill_summary_revisions.none?
        if bill.summary.present? && bill.summary.to_s.strip != Bill::SUMMARY_PLACEHOLDER && bill.summary != summary_markdown
          create!(
            bill: bill,
            summary_markdown: bill.summary,
            origin: "initial_baseline",
            publication_role: "published",
            review_state: "unknown",
            actor: nil,
            created_at: bill.updated_at || Time.current
          )
        end
      end

      latest = bill.bill_summary_revisions.order(created_at: :desc, id: :desc).first
      restored_id = restored_from.is_a?(BillSummaryRevision) ? restored_from.id : restored_from

      if latest &&
          latest.summary_markdown == summary_markdown &&
          latest.origin == origin.to_s &&
          latest.publication_role == publication_role.to_s &&
          latest.review_state == review_state.to_s &&
          latest.actor_id == actor&.id &&
          latest.llm_provider == llm_provider &&
          latest.llm_model == llm_model &&
          latest.restored_from_id == restored_id &&
          latest.news_source_snapshot_id == snapshot_id
        return latest
      end

      attrs = {
        bill: bill,
        summary_markdown: summary_markdown,
        origin: origin.to_s,
        publication_role: publication_role.to_s,
        review_state: review_state.to_s,
        actor: actor,
        llm_provider: llm_provider,
        llm_model: llm_model,
        restored_from_id: restored_id,
        created_at: created_at,
        news_source_snapshot_id: snapshot_id
      }.compact

      create!(attrs)
    end
  end

  private

  def capture_initial_baseline
    return if initial_baseline?
    return if bill.nil? || bill.summary.blank? || bill.summary.to_s.strip == Bill::SUMMARY_PLACEHOLDER
    return if bill.summary == summary_markdown
    return if BillSummaryRevision.where(bill_id: bill_id).exists?

    BillSummaryRevision.create!(
      bill_id: bill_id,
      summary_markdown: bill.summary,
      origin: "initial_baseline",
      publication_role: "published",
      review_state: "unknown",
      actor_id: nil,
      created_at: bill.updated_at || Time.current
    )
  end

  def restored_from_belongs_to_same_bill
    target = restored_from
    return if target.nil?

    if target.bill_id != bill_id
      errors.add(:restored_from, "must belong to the same bill")
    end
  end

  def news_source_snapshot_belongs_to_same_bill
    target = news_source_snapshot
    return if target.nil?

    if target.bill_id != bill_id
      errors.add(:news_source_snapshot, "must belong to the same bill")
    end
  end

  def prevent_mutation
    raise ActiveRecord::ReadOnlyRecord, "BillSummaryRevision records are immutable"
  end
end
