# frozen_string_literal: true

# == Schema Information
#
# Table name: users
# Database name: primary
#
#  id                                      :integer          not null, primary key
#  current_sign_in_at                      :datetime
#  current_sign_in_ip                      :string
#  email                                   :string
#  full_name                               :string
#  is_email_verified                       :boolean
#  is_phone_verified                       :boolean
#  is_registered_to_vote                   :boolean
#  is_registration_complete                :boolean
#  is_voter_registration_address_confirmed :boolean          default(FALSE), not null
#  last_sign_in_at                         :datetime
#  last_sign_in_ip                         :string
#  notify_on_new_position_default          :boolean          default(TRUE), not null
#  notify_on_summary_change_default        :boolean          default(TRUE), not null
#  notify_on_support_change_default        :boolean          default(TRUE), not null
#  org_position_cadence_default            :integer          default("every_change"), not null
#  phone                                   :string
#  registration_status                     :string           default("pending")
#  sign_in_count                           :integer          default(0), not null
#  sms_notifications_enabled               :boolean          default(FALSE)
#  theme                                   :string           default("neutral"), not null
#  theme_mode                              :string           default("light"), not null
#  created_at                              :datetime         not null
#  updated_at                              :datetime         not null
#  webauthn_id                             :string
#
# Indexes
#
#  index_users_on_email        (email) UNIQUE
#  index_users_on_phone        (phone) UNIQUE
#  index_users_on_webauthn_id  (webauthn_id) UNIQUE
#
class User < ApplicationRecord
  class << self
    private

    # @lat: [[identity-and-access#The phone number is the account#Admin and API phone lists represent separate privileges]]
    def phone_list_from_credential(name)
      (EnvSecret.read(name) || "").split(",").map(&:normalize_phone).compact_blank.freeze
    end
  end

  MIN_PASSKEY_COUNT = 1
  ADMIN_PHONES = phone_list_from_credential("ADMIN_PHONES")
  API_USER_PHONES = phone_list_from_credential("API_USER_PHONES")

  class EmailValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, value)
      return true if value.blank?

      email = prepare(value)

      unless URI::MailTo::EMAIL_REGEXP.match?(email)
        record.errors.add(attribute, options[:message] || "is not an email")
      end

      record.errors.add(attribute, "is not valid") if in_blocklist?(email)
    end

    def in_blocklist?(email)
      return false unless Rails.env.production?

      extra_blocked = %w[simplelogin.com mozmail.com privaterelay.appleid.com]
      block_list =
        Rails
          .cache
          .fetch("email_blocklist") do
            path = Constants::DISPOSABLE_EMAIL_BLOCKLIST_FILE_PATH
            # @lat: [[identity-and-access#The phone number is the account#Email is contact data, not an authentication path]]
            if File.exist?(path)
              File.read(path).split("\n") + extra_blocked
            else
              SwayLogging.warn("EmailValidator: blocklist file missing at #{path}; using fallback set only")
              extra_blocked
            end
          end

      return false if block_list.blank?
      return true if email.blank?

      suffix = email.split("@").last
      block_list.include?(suffix)
    end

    def prepare(value)
      value.strip.downcase
    end
  end

  # @lat: [[personal-detail-encryption#What is encrypted on a user]]
  encrypts :full_name
  encrypts :email, deterministic: true
  # @lat: [[personal-detail-encryption#Why the phone number takes the weaker mode]]
  encrypts :phone, deterministic: true
  encrypts :current_sign_in_ip
  encrypts :last_sign_in_ip

  has_many :user_address_changes, dependent: :destroy
  has_one :user_address, dependent: :destroy
  has_one :address, through: :user_address, dependent: :destroy

  has_many :api_keys, as: :bearer, dependent: :destroy

  has_many :user_organization_memberships, dependent: :destroy
  has_many :organizations, through: :user_organization_memberships
  has_many :received_organization_invites,
    class_name: "UserOrganizationMembershipInvite",
    foreign_key: :invitee_user_id,
    inverse_of: :invitee_user,
    dependent: :nullify
  # @lat: [[domain-entities#Organizations and campaigns]]
  has_many :organization_follows, dependent: :destroy
  has_many :followed_organizations, through: :organization_follows, source: :organization

  # @lat: [[org-notification-cascade-and-defaults#Notification records are destroyed through user associations]]
  has_many :pending_organization_digest_entries, class_name: "PendingOrganizationDigestEntry", dependent: :destroy
  has_many :pending_org_digest_entries, class_name: "PendingOrganizationDigestEntry", dependent: :destroy

  # @lat: [[org-notification-cascade-and-defaults#Notification records are destroyed through user associations]]
  has_many :organization_notification_deliveries, class_name: "OrganizationNotificationDelivery", dependent: :destroy
  has_many :org_notification_deliveries, class_name: "OrganizationNotificationDelivery", dependent: :destroy
  # @lat: [[news-article-evidence#Discovery request receipt]]
  has_many :news_article_discovery_requests, foreign_key: :requested_by_id, inverse_of: :requested_by, dependent: :restrict_with_error

  # @lat: [[org-notification-cascade-and-defaults#Org-notification cascade and defaults#User and follow cadence enums keep the same integer mapping]]
  enum :org_position_cadence_default,
    {every_change: 0, daily: 1, weekly: 2},
    default: :every_change

  # @lat: [[org-notification-cascade-and-defaults#Only supported follow preferences can be cascaded]]
  CASCADABLE_FOLLOW_COLUMNS = %i[
    notify_on_new_position
    notify_on_support_change
    notify_on_summary_change
  ].freeze

  has_one :user_invite_link, inverse_of: :user, dependent: :destroy
  has_one :refresh_token, dependent: :destroy

  has_many :push_notification_subscriptions, dependent: :destroy
  has_many :bill_summary_reports, inverse_of: :user, dependent: :nullify
  has_many :resolved_bill_summary_reports,
    class_name: "BillSummaryReport",
    foreign_key: :resolved_by_id,
    inverse_of: :resolved_by,
    dependent: :nullify

  has_many :passkeys, dependent: :destroy
  has_many :user_legislators, dependent: :destroy
  has_many :user_votes, dependent: :destroy
  has_many :user_bill_reminders, dependent: :destroy
  has_many :user_bill_shares, dependent: :destroy

  # @lat: [[reconcile-user-districts-service-design#Why the comparison happens at two levels]]
  has_many :user_districts, dependent: :destroy

  has_many :user_devices, dependent: :destroy
  has_many :notification_preferences, dependent: :destroy
  has_many :registration_funnel_events, dependent: :nullify
  has_many :representative_reassignments, dependent: :destroy

  attr_accessor :transient_funnel_metadata

  # @lat: [[identity-and-access#Sessions, cookies and bearer tokens#Signing out every device is atomic]]
  def revoke_all_devices!
    transaction do
      user_devices.active.find_each(&:revoke!)
    end
    ActionCable.server.remote_connections.where(current_user: self).disconnect
  end

  state_machine :registration_status, initial: :pending do
    event :start_processing do
      transition pending: :processing
    end

    event :complete do
      transition pending: :completed, if: :registered?
      transition processing: :completed, if: :registered?
      transition completed: :completed, if: :registered?
      # @lat: [[identity-and-access#Registration is asynchronous by necessity]]
      transition failed: :completed, if: :registered?
    end

    event :mark_failed do
      transition processing: :failed
    end

    after_transition on: :start_processing do |user, _transition|
      user.record_funnel_event(:geocoding_queued)
    end

    after_transition on: :complete do |user, transition|
      user.update(is_registration_complete: user.registered?)
      unless transition.from == :completed
        user.record_funnel_event(:geocoding_completed, user.transient_funnel_metadata || {})
      end
    end

    after_transition on: :mark_failed do |user, _transition|
      user.record_funnel_event(:geocoding_failed, user.transient_funnel_metadata || {})
    end

    # @lat: [[identity-and-access#Registration is asynchronous by necessity]]
    after_failure on: :complete do |user, _transition|
      user.update(is_registration_complete: user.registered?)
    end
  end

  validates :phone,
    presence: true,
    uniqueness: true,
    length: {
      minimum: 10,
      maximum: 10
    }
  validates :email, email: true, uniqueness: {allow_nil: true}
  validates :full_name, format: {with: /\A[a-z ,.'-]+\z/i, allow_nil: true}

  # @lat: [[preferences-controller-notes#Why a theme_id-only PATCH skips the User.update call entirely]]
  THEME_MODES = %w[auto light dark].freeze
  validates :theme_mode, inclusion: {in: THEME_MODES}

  after_initialize { self.webauthn_id ||= WebAuthn.generate_user_id }

  before_create do
    self.is_email_verified = false if is_email_verified.nil?
    self.is_phone_verified = false if is_phone_verified.nil?
    self.is_registration_complete = false if is_registration_complete.nil?
    self.is_registered_to_vote = false if is_registered_to_vote.nil?
    self.sms_notifications_enabled = false if sms_notifications_enabled.nil?

    self.sign_in_count ||= 0
  end

  before_save { self.phone = phone&.normalize_phone }

  after_create_commit :create_user_invite_url

  def sway_locales
    a = address
    a ? a.sway_locales : []
  end

  # @lat: [[request-locale-selection#Default locale selection prefers declared jurisdictions]]
  def default_sway_locale
    locales = sway_locales
    declared = locales.select(&:declared?)
    declared.find { |s| !s.congress? } || declared.first || locales.find { |s| !s.congress? } || locales.first
  end

  def user_legislators_by_locale(sway_locale)
    return [] unless sway_locale

    # @lat: [[legislator-history-serialization#Why locale filtering uses the legislator sway locale column]]
    user_legislators
      .where(active: true)
      .joins(:legislator)
      .where(legislators: {sway_locale_id: sway_locale.id})
      .includes(legislator: {district: :sway_locale})
      .to_a
  end

  def legislators(sway_locale)
    user_legislators_by_locale(sway_locale).map(&:legislator)
  end

  def districts(sway_locale)
    legislators(sway_locale).filter_map(&:district).uniq(&:id)
  end

  def email_sendable?
    !!is_email_verified && email.present?
  end

  # @lat: [[identity-and-access#User JSON exposes only selected fields]]
  def as_json(_options = {})
    to_sway_json
  end

  def to_builder
    Jbuilder.new do |user|
      user.id id
      user.full_name full_name
      user.email email
      user.phone phone
      user.invite_url invite_url
      user.is_email_verified is_email_verified
      user.is_registration_complete registered?
      user.registration_status registration_status
      user.is_registered_to_vote is_registered_to_vote
      user.sms_notifications_enabled sms_notifications_enabled

      # @lat: [[identity-and-access#User JSON exposes only selected fields]]
      user.theme_mode theme_mode

      user.is_admin is_sway_admin? if is_sway_admin?
      user.is_sway_admin is_sway_admin? if is_sway_admin?
      user.beszel_url beszel_url if beszel_url
    end
  end

  alias_attribute :organization_position_notification_cadence_default, :org_position_cadence_default

  def is_admin?
    is_sway_admin?
  end

  def is_sway_admin?
    ADMIN_PHONES.include?(phone)
  end
  alias_method :sway_admin?, :is_sway_admin?

  # @lat: [[admin-hub-index#Who sees the monitoring link]]
  def monitoring_admin?
    return false unless is_sway_admin?

    _local, at, domain = email.to_s.strip.downcase.rpartition("@")
    return false if at.empty? || domain.empty?

    Sway::Settings.ops.beszel_admin_email_domains.any? do |allowed|
      allowed.downcase.delete_prefix("@") == domain
    end
  end

  def beszel_url
    return nil unless monitoring_admin?

    configured = Sway::Settings.ops.beszel_url
    return configured if configured.present?

    host = SwayDeployConfig["SWAY_HOST"]
    return nil if host.blank?

    "http://#{host}:8090"
  end

  def is_sway_api_user?
    API_USER_PHONES.include?(phone)
  end

  def has_sway_passkey?
    passkeys.size.positive?
  end

  # @lat: [[identity-and-access#Registration is asynchronous by necessity]]
  def registered?
    user_legislators.where(active: true).exists?
  end

  def create_user_invite_url
    return if user_invite_link.present?

    UserInviteLink.from(user: self)
  end

  def invite_url
    user_invite_link&.short_url
  end

  # @lat: [[org-notification-cascade-and-defaults#Turning a user default off disables existing follows]]
  def cascade_org_pref_off!(column)
    column = column.to_sym if column.respond_to?(:to_sym)

    unless CASCADABLE_FOLLOW_COLUMNS.include?(column)
      raise ArgumentError,
        "#{column.inspect} is not a cascadable follow column. Allowed: #{CASCADABLE_FOLLOW_COLUMNS.inspect}"
    end

    organization_follows.update_all(column => false, :updated_at => Time.current)
  end

  def apply_org_notification_defaults!(attrs)
    user_attrs = attrs.respond_to?(:to_h) ? attrs.to_h.stringify_keys : attrs.stringify_keys
    bool = ActiveRecord::Type::Boolean.new

    previous = {
      notify_on_new_position_default: notify_on_new_position_default,
      notify_on_support_change_default: notify_on_support_change_default,
      notify_on_summary_change_default: notify_on_summary_change_default
    }

    %i[
      notify_on_new_position_default
      notify_on_support_change_default
      notify_on_summary_change_default
    ].each do |key|
      user_attrs[key.to_s] = bool.cast(user_attrs[key.to_s]) if user_attrs.key?(key.to_s)
    end

    return false unless update(user_attrs)

    {
      notify_on_new_position_default: :notify_on_new_position,
      notify_on_support_change_default: :notify_on_support_change,
      notify_on_summary_change_default: :notify_on_summary_change
    }.each do |default_col, follow_col|
      new_val = public_send(default_col)
      next unless previous[default_col] && new_val == false

      cascade_org_pref_off!(follow_col)
    end

    true
  end

  def record_funnel_event(step, metadata = {})
    last_event = registration_funnel_events.order(created_at: :desc).first
    v_token = last_event&.visitor_token || SecureRandom.uuid
    attr_key = last_event&.attribution_key

    normalized_step = RegistrationFunnelEvent.normalize_step(step).to_s
    already_completed = registration_funnel_events.where(step: RegistrationFunnelEvent.steps[:geocoding_completed]).exists?
    bot = RegistrationFunnelEvent.bot_traffic?(user: self)

    event = registration_funnel_events.create!(
      visitor_token: v_token,
      attribution_key: attr_key,
      step: normalized_step,
      metadata: metadata,
      bot: bot,
      created_at: Time.current
    )
    RegistrationFunnelEvent.mark_visitor_human!(v_token) if last_event&.visitor_token.present? && !bot

    if normalized_step == "geocoding_completed" && attr_key.present? && !already_completed
      ArticleEngagementTrackerService.track_registration(attribution_key: attr_key)
    end

    event
  rescue => e
    Rails.logger.error("Failed to record registration funnel event #{step} for user #{id}: #{e.message}")
    nil
  end
end
