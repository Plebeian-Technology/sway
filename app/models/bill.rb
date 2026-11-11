# frozen_string_literal: true

# == Schema Information
#
# Table name: bills
# Database name: primary
#
#  id                         :integer          not null, primary key
#  active                     :boolean
#  amendment_source           :string
#  archived_at                :datetime
#  audio_bucket_path          :string
#  audio_by_line              :string
#  category                   :string           default(""), not null
#  chamber                    :string           not null
#  external_version           :string
#  extracted_text             :text
#  house_vote_date_time_utc   :datetime
#  introduced_date_time_utc   :datetime         not null
#  last_seeded_at             :datetime
#  link                       :string
#  parsed_at                  :datetime
#  parsing_target             :string
#  parsing_target_log         :string
#  scheduled_release_date_utc :date
#  senate_vote_date_time_utc  :datetime
#  status                     :string
#  summary                    :text
#  title                      :string           not null
#  vote_import_state          :string           default("unimported"), not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  external_id                :string           not null
#  legislative_session_id     :integer
#  legislator_id              :integer          not null
#  sway_locale_id             :integer          not null
#
# Indexes
#
#  idx_bills_on_amendment_source                                 (amendment_source)
#  idx_bills_on_parsing_target                                   (parsing_target)
#  index_bills_on_external_id_and_sway_locale_id                 (external_id,sway_locale_id) UNIQUE
#  index_bills_on_legislative_session_id                         (legislative_session_id)
#  index_bills_on_legislator_id                                  (legislator_id)
#  index_bills_on_locale_and_release_date                        (sway_locale_id,scheduled_release_date_utc)
#  index_bills_on_scheduled_release_date_utc_and_sway_locale_id  (scheduled_release_date_utc,sway_locale_id) UNIQUE
#  index_bills_on_sway_locale_id                                 (sway_locale_id)
#  index_bills_on_sway_locale_id_and_archived_at                 (sway_locale_id,archived_at)
#  index_bills_on_vote_import_state                              (vote_import_state)
#
# Foreign Keys
#
#  legislative_session_id  (legislative_session_id => legislative_sessions.id) ON DELETE => nullify
#  legislator_id           (legislator_id => legislators.id)
#  sway_locale_id          (sway_locale_id => sway_locales.id)
#

class Bill < ApplicationRecord
  belongs_to :legislator
  belongs_to :sway_locale
  # @lat: [[locale-extension#Legislative session schema and validations]]
  belongs_to :legislative_session, optional: true

  # @lat: [[bill-session-archiving#Bill session archiving#Active views]]
  default_scope(all_queries: true) { where(archived_at: nil) }

  has_one :bill_score, dependent: :destroy
  has_one :bill_notification, dependent: :destroy
  has_one :bill_llm_provisioning, dependent: :destroy
  # @lat: [[bill-creator-summary-tab#Why the record of a run is kept at run time]]
  has_one :bill_summary_prompt_snapshot, dependent: :destroy
  # @lat: [[bill-creator-summary-tab#Planned recoverable summary history]]
  has_many :bill_summary_revisions, dependent: :delete_all

  # @lat: [[legislation-pipeline#Artifacts are files, not rows]]
  has_many :bill_cosponsors, dependent: :destroy
  has_many :roll_calls, -> { order(:created_at) }, inverse_of: :bill, dependent: :destroy
  has_many :legislator_votes, inverse_of: :bill, dependent: :destroy
  has_many :organization_bill_positions, inverse_of: :bill, dependent: :destroy
  # @lat: [[domain-entities#Bills]]
  has_many :active_organization_bill_positions,
    -> { where(active: true) },
    class_name: "OrganizationBillPosition",
    inverse_of: :bill
  has_many :organizations, through: :active_organization_bill_positions
  # @lat: [[campaign-approval#Approving a campaign from a testimony draft#A campaign belongs to one bill]]
  # @lat: [[domain-entities#Domain entities#Bills]]
  has_many :campaigns, inverse_of: :bill, dependent: :destroy
  has_many :sending_service_domain_bills, inverse_of: :bill, dependent: :destroy
  has_many :testimony_coverage_acknowledgements, inverse_of: :bill, dependent: :destroy
  # @lat: [[legislation-pipeline#Runs, resume and restart]]
  has_many :legislation_pipeline_runs, inverse_of: :bill, dependent: :nullify
  has_many :bill_summary_reports, inverse_of: :bill, dependent: :destroy
  has_many :article_bills, dependent: :destroy
  has_many :partner_organizations, through: :article_bills, source: :organization
  has_many :news_article_source_snapshots, inverse_of: :bill, dependent: :delete_all
  has_many :bill_news_articles, inverse_of: :bill, dependent: :destroy
  has_many :news_articles, through: :bill_news_articles
  has_many :news_article_testimonies, through: :bill_news_articles
  has_many :news_article_source_uses, through: :bill_news_articles, source: :source_uses
  has_many :news_article_discovery_requests, inverse_of: :bill, dependent: :destroy
  has_many :user_bill_shares, dependent: :destroy

  # @lat: [[legislation-pipeline#Parsed references are replaced together]]
  has_many :bill_section_references, dependent: :destroy, inverse_of: :bill
  has_many :bill_amendment_operations, dependent: :destroy, inverse_of: :bill

  has_many :bill_categories, dependent: :destroy
  # @lat: [[query-plan-indexes#A query-cost guard measures growth, not a ceiling]]
  has_many :categories, -> { order(:name) }, through: :bill_categories

  # @lat: [[legislation-pipeline#Runs, resume and restart#Which run the Bill Creator surfaces]]
  has_one :latest_legislation_pipeline_run,
    -> { order(created_at: :desc) },
    class_name: "LegislationPipelineRun",
    inverse_of: :bill

  # @lat: [[bill-interesting-score-design#Why Bill needs dependent: :delete_all on bill_interesting_scores]]
  has_many :bill_interesting_scores, dependent: :delete_all

  # @lat: [[bill-interesting-score-design#Why BillInterestingScoreCalculator is built this way]]
  has_one :latest_bill_interesting_score,
    -> { order(id: :desc) },
    class_name: "BillInterestingScore",
    inverse_of: :bill

  before_validation :downcase_status
  # @lat: [[bill-external-id-normalisation#Callback placement]]
  before_validation :normalize_external_id
  # @lat: [[unlinked-bill-presentation#The absent shape eliminates sentinel leakage]]
  before_validation :normalize_link
  # @lat: [[bill-session-archiving#Bill session archiving#Stale records]]
  before_update :require_visible_record
  before_destroy :require_visible_record, prepend: true
  after_create_commit :create_default_bill_score

  # @lat: [[bill-score-recompute-callback-split#Why score recompute uses two callbacks, not one#Bill trigger fields separate vote fetching from score recomputation]]
  VOTE_TRIGGER_FIELDS = %w[
    external_id external_version chamber status
    house_vote_date_time_utc senate_vote_date_time_utc
  ].freeze

  after_commit :enqueue_legislator_vote_fetch, on: :update,
    if: -> { VOTE_TRIGGER_FIELDS.any? { |f| saved_change_to_attribute?(f) } }

  # @lat: [[bill-score-recompute-callback-split#Why score recompute uses two callbacks, not one#Bill trigger fields separate vote fetching from score recomputation]]
  SCORE_TRIGGER_FIELDS = %w[
    house_vote_date_time_utc senate_vote_date_time_utc sway_locale_id
  ].freeze

  # @lat: [[bill-score-recompute-callback-split#Why score recompute uses two callbacks, not one]]
  after_create_commit :enqueue_interesting_score_recompute_on_create
  after_commit :enqueue_interesting_score_recompute, on: :update,
    if: -> { SCORE_TRIGGER_FIELDS.any? { |f| saved_change_to_attribute?(f) } }

  validates :external_id,
    :chamber,
    :introduced_date_time_utc,
    :status,
    :summary,
    :title,
    :sway_locale_id,
    :legislator_id,
    presence: {
      message: "%<attribute>s can't be blank"
    }
  validates :external_id,
    uniqueness: {
      scope: :sway_locale_id,
      allow_nil: true
    }
  # rubocop:disable Rails/UniqueValidationWithoutIndex
  validates :link,
    uniqueness: {
      allow_nil: true
    }
  # rubocop:enable Rails/UniqueValidationWithoutIndex

  # @lat: [[bill-external-id-validation#Why external IDs require path validation]]
  EXTERNAL_ID_PATTERN = ::Legislation::Paths::EXTERNAL_ID_PATTERN

  # @lat: [[bill-external-id-normalisation#Why the check is conditional]]
  validates :external_id,
    format: {
      with: EXTERNAL_ID_PATTERN,
      message: "must be a single path-safe segment (letters, digits, . _ -), 1-64 characters"
    },
    if: :external_id_changed?

  def self.of_the_month(sway_locale:)
    b =
      where(
        sway_locale:,
        scheduled_release_date_utc: Time.zone.today - 1.month..Time.zone.today
      ).order(scheduled_release_date_utc: :desc).limit(1).first

    b.presence ||
      where(sway_locale:)
        .order(scheduled_release_date_utc: :desc)
        .limit(1)
        .first
  end

  # @lat: [[bills-controller-design#The web bills index grows a stable page window#Past Bills of the Month vs All Bills and historical sessions]]
  def self.past_of_the_month(sway_locale:)
    return none if sway_locale.nil?

    scope =
      where(sway_locale:)
        .where.not(scheduled_release_date_utc: nil)
        .where(scheduled_release_date_utc: ..Time.zone.today)
    current = of_the_month(sway_locale:)
    current ? scope.where.not(id: current.id) : scope
  end

  def self.for_legislative_session(session)
    return none if session.nil?

    base = session.active? ? all : unscope(where: :archived_at)
    rel = base.where(sway_locale_id: session.sway_locale_id)
    assigned = rel.where(legislative_session_id: session.id)
    fallback_rel = fallback_relation_for_sessions(rel, [session])

    fallback_rel ? assigned.or(fallback_rel) : assigned
  end

  def self.current_legislative_session(sway_locale = nil)
    sessions = active_sessions_for(sway_locale)
    return none if sessions.empty?

    rel = all
    if sway_locale.present?
      locale_id = sway_locale.is_a?(SwayLocale) ? sway_locale.id : sway_locale
      rel = rel.where(sway_locale_id: locale_id)
    end

    assigned_to_active = rel.where(legislative_session_id: sessions.map(&:id))
    fallback_rel = fallback_relation_for_sessions(rel, sessions)

    fallback_rel ? assigned_to_active.or(fallback_rel) : assigned_to_active
  end

  class << self
    alias_method :current_session, :current_legislative_session
  end

  def self.active_sessions_for(sway_locale)
    if sway_locale.present?
      locale_id = sway_locale.is_a?(SwayLocale) ? sway_locale.id : sway_locale
      LegislativeSession.where(sway_locale_id: locale_id, active: true).to_a
    else
      Rails.logger.debug "current_legislative_session called with nil sway_locale"
      Sentry.capture_message("current_legislative_session called with nil sway_locale", level: :warning)
      LegislativeSession.where(active: true).to_a
    end
  end
  private_class_method :active_sessions_for

  def self.fallback_relation_for_sessions(base_relation, sessions)
    fallback_conditions = sessions.map do |session|
      base_relation.where(
        legislative_session_id: nil,
        sway_locale_id: session.sway_locale_id,
        introduced_date_time_utc: session.start_date.beginning_of_day..session.end_date.end_of_day
      )
    end

    fallback_conditions.reduce { |combined, condition| combined.or(condition) }
  end
  private_class_method :fallback_relation_for_sessions

  class Status
    PASSED = "passed"
    FAILED = "failed"
    COMMITTEE = "committee"
    VETOED = "vetoed"
  end

  STATUSES = [
    Status::PASSED.freeze,
    Status::FAILED.freeze,
    Status::COMMITTEE.freeze,
    Status::VETOED.freeze
  ].freeze

  # @lat: [[bill-status-normalisation#The allowlist is checked on the way in, not on the way past]]
  validates :status,
    inclusion: {
      in: STATUSES,
      message: "%<value>s is not one of #{STATUSES.join(", ")}"
    },
    if: :status_changed?

  def active
    return false if archived_at.present?

    session = legislative_session
    if session
      session.active?
    else
      super.nil? || super
    end
  end
  alias_method :active?, :active

  def require_visible_record
    return if self.class.exists?(id)

    errors.add(:base, "Archived bills cannot be changed or deleted")
    throw :abort
  end

  def roll_call
    roll_calls.last
  end
  alias_method :vote, :roll_call

  def notifyable?
    scheduled_release_date_utc == Time.zone.today && bill_notification.nil?
  end

  # @lat: [[news-article-evidence#Changes after publication]]
  def related_articles
    if bill_news_articles.loaded?
      bill_news_articles.to_a.select(&:approved?)
    else
      bill_news_articles.approved.includes(:news_article)
    end
  end

  # @lat: [[news-article-evidence#Changes after publication]]
  def news_testimonies
    if news_article_testimonies.loaded?
      news_article_testimonies.to_a.select { |t| t.published? && t.currently_eligible? }
    else
      news_article_testimonies
        .published
        .includes(bill_news_article: %i[news_article current_text_version])
        .select(&:currently_eligible?)
    end
  end

  # @lat: [[lazy-inertia-props#Lazy Inertia props#Current optional and deferred JSON props]]
  def render(current_user, current_sway_locale, district_legislator_names: false)
    BillResource.page_props(self, current_user:, current_sway_locale:, district_legislator_names:)
  end

  # @lat: [[ai-unreviewed-notice-component-design#AiUnreviewedNotice component design#The pending-summary sentinel is not published AI text]]
  SUMMARY_PLACEHOLDER = "Summary pending"

  # @lat: [[ai-unreviewed-notice-component-design#AiUnreviewedNotice component design#The server sends a derived boolean, not the source text]]
  def summary_ai_unreviewed?
    return false if summary.blank? || summary.to_s.strip == SUMMARY_PLACEHOLDER

    pub_rev = current_published_summary_revision
    if pub_rev
      return false if pub_rev.summary_markdown != summary

      return pub_rev.review_state == "unreviewed"
    end

    provisioning = bill_llm_provisioning
    return false if provisioning.nil?

    draft = provisioning.llm_summary
    return false if draft.blank?
    return false if provisioning.llm_provider == BillLlmProvisioning::OPERATOR_PASTE_PROVIDER

    summary.to_s == draft.to_s
  end

  def current_published_summary_revision
    if bill_summary_revisions.loaded?
      bill_summary_revisions
        .select { |r| r.publication_role == "published" }
        .max_by { |r| [r.created_at || Time.zone.at(0), r.id || 0] }
    else
      bill_summary_revisions
        .where(publication_role: "published")
        .order(created_at: :desc, id: :desc)
        .first
    end
  end

  def restore_summary_revision!(revision, actor: nil, news_usage: nil, source_uses: nil)
    raise ArgumentError, "Revision must belong to this bill" if revision.bill_id != id

    with_lock do
      res = ManualNewsSummaryPublicationService.publish!(
        bill: self,
        summary_markdown: revision.summary_markdown,
        actor: actor,
        origin: "restoration",
        news_usage: news_usage,
        source_uses: source_uses,
        snapshot: revision.news_source_snapshot,
        snapshot_id: revision.news_source_snapshot_id,
        restored_from: revision,
        review_state: revision.review_state
      )
      res.revision
    end
  end

  def to_builder
    Jbuilder.new do |b|
      b.id id
      b.external_id external_id
      b.external_version external_version
      b.title title
      b.summary summary
      # @lat: [[ai-unreviewed-notice-component-design#AiUnreviewedNotice component design#The server sends a derived boolean, not the source text]]
      b.summary_ai_unreviewed summary_ai_unreviewed?
      b.link link
      b.chamber chamber
      b.category category
      b.status status
      b.active active

      b.scheduled_release_date_utc scheduled_release_date_utc

      b.audio_bucket_path audio_bucket_path
      b.audio_by_line audio_by_line

      b.vote_date_time_utc vote_date_time_utc
      b.introduced_date_time_utc introduced_date_time_utc
      b.house_vote_date_time_utc house_vote_date_time_utc
      b.senate_vote_date_time_utc senate_vote_date_time_utc
      b.vote vote&.to_sway_json
      # @lat: [[query-plan-indexes#Index shapes the query planner can use#A query-cost guard measures growth, not a ceiling]]
      b.categories categories.select(&:active?).map(&:name)

      b.legislator_id legislator_id
      b.sway_locale_id sway_locale_id

      b.created_at created_at
    end
  end

  # @lat: [[bill-vote-date#The shared bill vote date]]
  def vote_date_time_utc
    h = house_vote_date_time_utc
    s = senate_vote_date_time_utc
    return nil unless h || s

    if h && s
      h.before?(s) ? h : s
    else
      h || s
    end
  end

  private

  # @lat: [[unlinked-bill-presentation#The absent shape eliminates sentinel leakage]]
  # steep:ignore:start
  def normalize_link
    self.link = link.presence&.strip
  end
  # steep:ignore:end

  # @lat: [[bill-external-id-normalisation#Why the strip runs before the format check]]
  def normalize_external_id
    value = external_id #: String?
    return if value.nil?

    stripped = value.strip
    self.external_id = stripped unless stripped == value
  end

  # @lat: [[bill-status-normalisation#An unrecognised status is left where it is]]
  def downcase_status
    s = status
    return unless s

    downcased = s.downcase
    self.status = downcased if STATUSES.include?(downcased)
  end

  # @lat: [[migrations-name-no-model#Migrations name no model#A uniqueness validation is not a constraint]]
  def create_default_bill_score
    BillScore.create_or_find_by!(bill: self)
  end

  # @lat: [[bill-score-recompute-callback-split#Why score recompute uses two callbacks, not one#Why repeated enqueues on the same bill are safe]]
  def enqueue_legislator_vote_fetch
    LegislatorVoteFetchJob.perform_later(id)
  end

  # @lat: [[bill-score-recompute-callback-split#Why score recompute uses two callbacks, not one#Why repeated enqueues on the same bill are safe]]
  def enqueue_interesting_score_recompute
    RecomputeBillInterestingScoreJob.perform_later(id)
  end

  # @lat: [[bill-score-recompute-callback-split#Why score recompute uses two callbacks, not one#Why the create hook needs its own method name]]
  def enqueue_interesting_score_recompute_on_create
    enqueue_interesting_score_recompute
  end
end
