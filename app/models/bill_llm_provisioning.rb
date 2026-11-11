# frozen_string_literal: true

# == Schema Information
#
# Table name: bill_llm_provisionings
# Database name: primary
#
#  id                               :integer          not null, primary key
#  categories_unmatched_at          :datetime
#  citations_valid                  :boolean
#  cleaned_testimony                :text
#  cleaned_testimony_at             :datetime
#  diff_content                     :text
#  diff_generated_at                :datetime
#  draft_org_positions              :text
#  extracted_testimony              :text
#  generation_error                 :text
#  generation_status                :string
#  hearings_fetched_at              :datetime
#  individual_campaign_draft_hashes :text
#  invalid_citations                :text
#  invalid_news_urls                :text
#  llm_full_breakdown               :text
#  llm_generated_at                 :datetime
#  llm_model                        :string
#  llm_provider                     :string
#  llm_summary                      :text
#  news_articles                    :text
#  news_articles_fetched_at         :datetime
#  news_urls_valid                  :boolean
#  rejected_campaign_draft_hashes   :text
#  summary_batch_expires_at         :datetime
#  summary_batch_testimony_digest   :string
#  supplemental_testimony           :text
#  testimony_attachments            :text
#  testimony_fetched_at             :datetime
#  created_at                       :datetime         not null
#  updated_at                       :datetime         not null
#  bill_id                          :integer          not null
#  summary_batch_id                 :string
#  summary_run_id                   :string
#
# Indexes
#
#  index_bill_llm_provisionings_on_bill_id                  (bill_id) UNIQUE
#  index_bill_llm_provisionings_on_categories_unmatched_at  (categories_unmatched_at) WHERE categories_unmatched_at IS NOT NULL
#  index_bill_llm_provisionings_on_llm_generated_at         (llm_generated_at)
#  index_bill_llm_provisionings_on_summary_batch_id         (summary_batch_id)
#  index_bill_llm_provisionings_on_summary_run_id           (summary_run_id) UNIQUE WHERE summary_run_id IS NOT NULL
#
# Foreign Keys
#
#  bill_id  (bill_id => bills.id)
#
class BillLlmProvisioning < ApplicationRecord
  belongs_to :bill

  serialize :draft_org_positions, coder: JSON
  serialize :testimony_attachments, coder: JSON
  serialize :invalid_citations, coder: JSON
  serialize :cleaned_testimony, coder: JSON
  serialize :rejected_campaign_draft_hashes, coder: JSON
  serialize :individual_campaign_draft_hashes, coder: JSON
  serialize :news_articles, coder: JSON
  serialize :invalid_news_urls, coder: JSON

  def news_articles_list
    Array(news_articles)
  end

  # @lat: [[campaign-draft-rejection#The problem: a campaign draft has no row]]
  def rejected_campaign_draft_hash_list
    Array(rejected_campaign_draft_hashes).map(&:to_s)
  end

  def reject_campaign_draft!(content_hash)
    hash = content_hash.to_s.strip
    return false if hash.empty?

    with_lock do
      list = rejected_campaign_draft_hash_list
      new_rejected = (list + [hash]).uniq
      new_individual = individual_campaign_draft_hash_list - [hash]

      next false if new_rejected == list && new_individual == individual_campaign_draft_hash_list

      update!(
        rejected_campaign_draft_hashes: new_rejected,
        individual_campaign_draft_hashes: new_individual
      )
      true
    end
  end

  # @lat: [[campaign-draft-rejection#Releasing drafts to individual letters]]
  def individual_campaign_draft_hash_list
    Array(individual_campaign_draft_hashes).map(&:to_s)
  end

  def mark_campaign_draft_individual!(content_hash)
    hash = content_hash.to_s.strip
    return false if hash.empty?

    with_lock do
      list = individual_campaign_draft_hash_list
      new_individual = (list + [hash]).uniq
      new_rejected = rejected_campaign_draft_hash_list - [hash]

      next false if new_individual == list && new_rejected == rejected_campaign_draft_hash_list

      update!(
        individual_campaign_draft_hashes: new_individual,
        rejected_campaign_draft_hashes: new_rejected
      )
      true
    end
  end

  def restore_campaign_draft!(content_hash)
    hash = content_hash.to_s.strip
    return false if hash.empty?

    with_lock do
      rejected_list = rejected_campaign_draft_hash_list
      individual_list = individual_campaign_draft_hash_list

      next false unless rejected_list.include?(hash) || individual_list.include?(hash)

      new_rejected = rejected_list - [hash]
      new_individual = individual_list - [hash]

      update!(
        rejected_campaign_draft_hashes: new_rejected,
        individual_campaign_draft_hashes: new_individual
      )
      true
    end
  end

  # @lat: [[pipeline-artifact-presence-overview#Cleaned-testimony freshness and letter offsets]]
  # @lat: [[testimony-mirror-rule#Why each made-up mirror row has its own wording]]

  # @lat: [[operator-paste-provenance-marker#LlmSummaryProvenanceChip]]
  # @lat: [[bill-summary-ai-unreviewed-detection#Pasted summaries are not machine words]]
  OPERATOR_PASTE_PROVIDER = "operator_paste"

  # @lat: [[draft-org-position-identity#Querying for a non-empty draft_org_positions]]
  DRAFT_TOKEN_HEX_CHARS = 16

  # @lat: [[draft-org-position-identity#Querying for a non-empty draft_org_positions]]
  def self.draft_token(entry)
    return nil unless entry.is_a?(::Hash)

    canonical = entry.transform_keys(&:to_s).sort.to_h
    Digest::SHA256.hexdigest(JSON.generate(canonical))[0, DRAFT_TOKEN_HEX_CHARS]
  end

  # @lat: [[draft-org-position-identity#Querying for a non-empty draft_org_positions]]
  def self.draft_identity_asserted?(name: nil, token: nil)
    token.present? || name.present?
  end

  # @lat: [[draft-field-validation#Why draft_text_too_long? treats a field with no cap as never too long]]
  DRAFT_POSITIONS = BILL_POSITIONS_SCHEMA_HASH
    .fetch("properties")
    .fetch("draft_org_positions")
    .fetch("items")
    .fetch("properties")
    .then { |props| (props["support"] || props["stance"]).fetch("enum") }
    .map(&:to_s)
    .freeze

  def self.draft_support_valid?(value)
    DRAFT_POSITIONS.include?(value.to_s)
  end

  class << self
    alias_method :draft_stance_valid?, :draft_support_valid?
  end

  # @lat: [[draft-field-validation#Why draft_text_too_long? treats a field with no cap as never too long]]
  DRAFT_TEXT_MAX_CHARS = begin
    text_properties = BILL_POSITIONS_SCHEMA_HASH
      .fetch("properties")
      .fetch("draft_org_positions")
      .fetch("items")
      .fetch("properties")
    {
      "org_name" => text_properties.fetch("org_name").fetch("maxLength"),
      "summary" => text_properties.fetch("summary").fetch("maxLength")
    }.freeze
  end

  # @lat: [[draft-field-validation#Why draft_text_too_long? treats a field with no cap as never too long]]
  def self.draft_text_too_long?(field, value)
    cap = DRAFT_TEXT_MAX_CHARS[field.to_s] #: Integer?
    return false if cap.nil?

    value.to_s.length > cap
  end

  # @lat: [[draft-org-position-identity#draft_org_positions_for_client: the version the browser sees]]
  def self.draft_identity_mismatch?(entry, name: nil, token: nil)
    return false unless draft_identity_asserted?(name: name, token: token)
    return draft_token(entry).to_s != token.to_s if token.present?

    entry_name = entry.is_a?(::Hash) ? entry["org_name"] : nil
    entry_name.to_s != name.to_s
  end

  # @lat: [[internal-draft-marks#INTERNAL_DRAFT_MARKS]]
  DRAFT_EVIDENCE_RETRACTED_KEY = "evidence_retracted_at"

  # @lat: [[evidence-retraction#Selective retraction between testimony and news evidence]]
  def self.drafts_with_evidence_retracted(raw, at: Time.current)
    return raw unless raw.is_a?(::Array)

    stamp = at.utc.iso8601
    raw.map do |entry|
      next entry unless entry.is_a?(::Hash)
      next entry if draft_news_sourced?(entry)
      next entry if draft_evidence_retracted?(entry)

      entry.merge(DRAFT_EVIDENCE_RETRACTED_KEY => stamp)
    end
  end

  # @lat: [[evidence-retraction#Reading the mark]]
  def self.draft_evidence_retracted?(entry)
    return false unless entry.is_a?(::Hash)

    (entry[DRAFT_EVIDENCE_RETRACTED_KEY] || entry[DRAFT_EVIDENCE_RETRACTED_KEY.to_sym]).present?
  end

  # @lat: [[evidence-retraction#Reading the mark]]
  def self.draft_news_sourced?(entry)
    return false unless entry.is_a?(::Hash)

    (entry["bill_news_article_id"] || entry[:bill_news_article_id]).present? ||
      (entry["text_version_id"] || entry[:text_version_id]).present? ||
      (entry["evidence_excerpt"] || entry[:evidence_excerpt]).present?
  end

  class << self
    alias_method :news_sourced_draft?, :draft_news_sourced?
  end

  # @lat: [[evidence-retraction#The frontend's IOrgPosition.evidence_retracted_at]]
  def self.drafts_with_news_evidence_retracted(raw, bill_news_article_id:, text_version_id: nil, at: Time.current)
    return raw unless raw.is_a?(::Array)
    return raw if bill_news_article_id.blank?

    stamp = at.utc.iso8601
    raw.map do |entry|
      next entry unless entry.is_a?(::Hash)
      next entry unless draft_news_sourced?(entry)

      entry_article_id = entry["bill_news_article_id"] || entry[:bill_news_article_id]
      next entry unless entry_article_id.present? && entry_article_id.to_s == bill_news_article_id.to_s

      if text_version_id.present?
        entry_text_version_id = entry["text_version_id"] || entry[:text_version_id]
        next entry if entry_text_version_id.present? && entry_text_version_id.to_s == text_version_id.to_s
      end

      next entry if draft_evidence_retracted?(entry)

      entry.merge(DRAFT_EVIDENCE_RETRACTED_KEY => stamp)
    end
  end

  # @lat: [[internal-draft-marks#INTERNAL_DRAFT_MARKS]]
  def self.draft_org_positions_preserving_marks(stored, pasted)
    return pasted unless stored.is_a?(::Array) && pasted.is_a?(::Array)

    marks_by_content = stored.each_with_object({}) do |entry, memo|
      next unless entry.is_a?(::Hash)

      marks = entry.slice(*INTERNAL_DRAFT_MARKS)
      memo[entry.except(*INTERNAL_DRAFT_MARKS)] = marks if marks.any?
    end
    return pasted if marks_by_content.empty?

    pasted.map do |entry|
      next entry unless entry.is_a?(::Hash)

      marks = marks_by_content[entry]
      marks ? entry.merge(marks) : entry
    end
  end

  # @lat: [[internal-draft-marks#INTERNAL_DRAFT_MARKS]]
  DRAFT_SUMMARY_EDITED_KEY = "summary_edited_at"

  # @lat: [[internal-draft-marks#INTERNAL_DRAFT_MARKS]]
  INTERNAL_DRAFT_MARKS = [DRAFT_EVIDENCE_RETRACTED_KEY, DRAFT_SUMMARY_EDITED_KEY].freeze

  # @lat: [[internal-draft-marks#INTERNAL_DRAFT_MARKS]]
  def self.draft_with_summary_edited(entry, previous_summary:, at: Time.current)
    return entry unless entry.is_a?(::Hash)
    return entry if entry["summary"].to_s == previous_summary.to_s
    return entry if entry[DRAFT_SUMMARY_EDITED_KEY].present?

    entry.merge(DRAFT_SUMMARY_EDITED_KEY => at.utc.iso8601)
  end

  # @lat: [[internal-draft-marks#INTERNAL_DRAFT_MARKS]]
  def self.draft_summary_edited?(entry)
    entry.is_a?(::Hash) && entry[DRAFT_SUMMARY_EDITED_KEY].present?
  end

  # @lat: [[skipped-run-notice-copy#The reclaim-sweep copy test notes (LlmSummaryStatusBranches.test.tsx)]]
  state_machine :generation_status, initial: nil do
    event :enqueue do
      transition from: nil, to: :pending
      transition from: :completed, to: :pending
      transition from: :failed, to: :pending
      transition from: :skipped, to: :pending
    end

    event :start_generating do
      transition pending: :generating
    end

    event :mark_completed do
      transition generating: :completed
    end

    # @lat: [[llm-summaries#A run that fails before it starts still settles]]
    event :mark_failed do
      transition generating: :failed
      transition pending: :failed
    end

    # @lat: [[skipped-run-notice-copy#Why mark_skipped only fires from pending]]
    event :mark_skipped do
      transition pending: :skipped
    end
  end

  # @lat: [[stale-change-detection#The two change-kind words are spelled once on each side]]
  TESTIMONY_CHANGE = "testimony"
  PIPELINE_DATA_CHANGE = "pipeline_data"

  # @lat: [[stale-change-detection#The two change-kind words are spelled once on each side]]
  def stale_change
    generated = llm_generated_at #: ActiveSupport::TimeWithZone?
    return nil if generated.nil?

    tested = testimony_fetched_at #: ActiveSupport::TimeWithZone?
    diffed = diff_generated_at #: ActiveSupport::TimeWithZone?
    testimony_at = (tested && tested > generated) ? tested : nil
    diff_at = (diffed && diffed > generated) ? diffed : nil

    return [TESTIMONY_CHANGE, testimony_at] if testimony_at && (diff_at.nil? || testimony_at >= diff_at)
    return [PIPELINE_DATA_CHANGE, diff_at] if diff_at

    nil
  end

  def stale?
    !stale_change.nil?
  end

  # @lat: [[llm-summaries#Batch summarisation#Why the per-bill exemption needs its own ceiling]]
  scope :reclaimable_candidates, -> {
    where(generation_status: %w[pending generating])
      .where(updated_at: ..GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.ago)
      .where("summary_batch_expires_at IS NULL OR summary_batch_expires_at <= ?", Time.current)
  }

  # @lat: [[llm-summaries#Runs are marked and reclaimable#Why the reclaim judgement lives on the row]]
  def reclaimable?
    return false unless pending? || generating?

    last_written_at = updated_at #: ActiveSupport::TimeWithZone?
    return false if last_written_at.nil?
    return false if last_written_at > GenerateBillSummaryService::RECLAIM_ABANDONED_AFTER.ago
    return false if summary_batch_awaited?

    true
  end

  # @lat: [[llm-summaries#Batch summarisation#Why the per-bill exemption needs its own ceiling]]
  def summary_batch_awaited?
    expires_at = summary_batch_expires_at
    return false if expires_at.nil?

    expires_at > Time.current
  end

  # @lat: [[positions-run-evidence#testimony_digest: a fingerprint of the evidence]]
  def testimony_present?
    extracted_testimony.present? || supplemental_testimony.present?
  end

  # @lat: [[positions-run-evidence#testimony_digest: a fingerprint of the evidence]]
  def testimony_digest
    ::Digest::SHA256.hexdigest([supplemental_testimony.to_s, extracted_testimony.to_s].join("\0"))
  end

  # @lat: [[positions-run-evidence#positions_owed?: is the call still owed?]]
  def positions_owed?
    return false unless draft_org_positions.nil?
    return testimony_present? if bill.nil?

    SummaryItemEligibility.new(bill: bill, provisioning: self).positions?
  end

  # @lat: [[bill-provisioning-payload#diff_generated_at is gone too]]
  def to_builder
    Jbuilder.new do |p|
      p.id id
      p.generation_status generation_status
      p.generation_error generation_error
      p.llm_summary llm_summary
      p.llm_full_breakdown llm_full_breakdown
      p.supplemental_testimony supplemental_testimony
      # @lat: [[draft-org-position-identity#draft_org_positions_for_client: the version the browser sees]]
      p.draft_org_positions draft_org_positions_for_client
      p.llm_provider llm_provider
      p.llm_model llm_model
      p.llm_generated_at llm_generated_at
      # @lat: [[bill-provisioning-payload#diff_content is not sent]]
      change = stale_change
      p.stale !change.nil?
      # @lat: [[stale-change-detection#What the marker used to read, and why it changed]]
      p.stale_change_kind change&.first
      p.stale_change_at change&.last
      # @lat: [[abandoned-run-reclaim#Why ReclaimAbandonedSummaryRunsJob exists]]
      p.reclaimable reclaimable?
      # @lat: [[abandoned-run-reclaim#Why ReclaimAbandonedSummaryRunsJob exists]]
      p.paste_owns_summary_run SummaryRunMarker.operator_paste?(summary_run_id)
      # @lat: [[bill-provisioning-payload#Why four testimony/citation fields stay on the older Jbuilder path]]
      p.has_testimony testimony_present?
      p.testimony_attachments testimony_attachments
      p.citations_valid citations_valid
      p.invalid_citations invalid_citations
    end
  end

  # @lat: [[draft-org-position-identity#draft_org_positions_for_client: the version the browser sees]]
  def draft_org_positions_for_client
    raw = draft_org_positions
    return raw unless raw.is_a?(::Array)

    raw.map do |entry|
      entry.is_a?(::Hash) ? entry.merge("draft_token" => self.class.draft_token(entry)) : entry
    end
  end
end
