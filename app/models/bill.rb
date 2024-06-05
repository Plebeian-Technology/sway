# typed: true

# == Schema Information
#
# Table name: bills
#
#  id                        :integer          not null, primary key
#  external_id               :string           not null
#  external_version          :string
#  title                     :string           not null
#  link                      :string
#  chamber                   :string           not null
#  introduced_date_time_utc  :datetime         not null
#  house_vote_date_time_utc  :datetime
#  senate_vote_date_time_utc :datetime
#  level                     :string           not null
#  category                  :string           not null
#  summary                   :text
#  legislator_id             :integer          not null
#  sway_locale_id            :integer          not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  status                    :string
#  active                    :boolean
#  audio_bucket_path         :string
#  audio_by_line             :string
#

class Bill < ApplicationRecord
  extend T::Sig

  belongs_to :legislator
  belongs_to :sway_locale

  has_one :bill_score

  has_many :bill_cosponsors
  has_many :votes, inverse_of: :bill
  has_many :legislator_votes, inverse_of: :bill
  has_many :organization_bill_positions, inverse_of: :bill

  before_save :downcase_status

  after_create :send_notifications

  validates_uniqueness_of :external_id, scope: :sway_locale_id, allow_nil: true

  scope :of_the_week, -> { last }

  class Status
    PASSED = 'passed'.freeze
    FAILED = 'failed'.freeze
    COMMITTEE = 'committee'.freeze
    VETOED = 'vetoed'.freeze
  end.freeze

  STATUSES = [Status::PASSED.freeze, Status::FAILED.freeze, Status::COMMITTEE.freeze, Status::VETOED.freeze].freeze

  sig { returns(SwayLocale) }
  def sway_locale
    T.cast(super, SwayLocale)
  end

  sig { returns(Legislator) }
  def legislator
    T.cast(super, Legislator)
  end

  def active
    if introduced_date_time_utc.before?(sway_locale.current_session_start_date)
      false
    else
      super.nil? ? true : super
    end
  end

  sig { returns(T.nilable(Vote)) }
  def vote
    votes.last
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |b|
      b.id id
      b.external_id external_id
      b.external_version external_version
      b.title title
      b.summary summary
      b.link link
      b.chamber chamber
      b.level level
      b.category category
      b.status status
      b.active active

      b.audio_bucket_path audio_bucket_path
      b.audio_by_line audio_by_line

      b.vote_date_time_utc vote_date_time_utc
      b.introduced_date_time_utc introduced_date_time_utc
      b.house_vote_date_time_utc house_vote_date_time_utc
      b.senate_vote_date_time_utc senate_vote_date_time_utc
      b.vote vote&.to_builder&.attributes!

      b.legislator_id legislator_id
      b.sway_locale_id sway_locale_id

      b.created_at created_at
    end
  end

  private

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

  sig { void }
  def downcase_status
    s = status
    return unless s

    if STATUSES.include?(s.downcase)
      self.status = s.downcase
    else
      Rails.logger.warn("Bill.downcase_status - received status of #{s} is NOT valid. Should be one of #{STATUSES.join(', ')}")
      self.status = nil
    end
  end

  sig { void }
  def send_notifications
    SwayPushNotificationService.new(
      title: 'New Bill of the Week',
      body: "#{title} in #{sway_locale.human_name}"
    ).send_push_notification
  end
end
