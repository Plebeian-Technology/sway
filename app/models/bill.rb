# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: bills
#
#  id                         :integer          not null, primary key
#  active                     :boolean
#  audio_bucket_path          :string
#  audio_by_line              :string
#  category                   :string           not null
#  chamber                    :string           not null
#  external_version           :string
#  house_vote_date_time_utc   :datetime
#  introduced_date_time_utc   :datetime         not null
#  level                      :string           not null
#  link                       :string
#  scheduled_release_date_utc :date
#  senate_vote_date_time_utc  :datetime
#  status                     :string
#  summary                    :text
#  title                      :string           not null
#  created_at                 :datetime         not null
#  updated_at                 :datetime         not null
#  external_id                :string           not null
#  legislator_id              :integer          not null
#  sway_locale_id             :integer          not null
#
# Indexes
#
#  index_bills_on_external_id_and_sway_locale_id                 (external_id,sway_locale_id) UNIQUE
#  index_bills_on_legislator_id                                  (legislator_id)
#  index_bills_on_scheduled_release_date_utc_and_sway_locale_id  (scheduled_release_date_utc,sway_locale_id) UNIQUE
#  index_bills_on_sway_locale_id                                 (sway_locale_id)
#
# Foreign Keys
#
#  legislator_id   (legislator_id => legislators.id)
#  sway_locale_id  (sway_locale_id => sway_locales.id)
#

class Bill < ApplicationRecord
  extend T::Sig

  belongs_to :legislator
  belongs_to :sway_locale

  has_one :bill_score, dependent: :destroy

  has_many :bill_cosponsors, dependent: :destroy
  has_many :votes, inverse_of: :bill, dependent: :destroy
  has_many :legislator_votes, inverse_of: :bill, dependent: :destroy
  has_many :organization_bill_positions, inverse_of: :bill, dependent: :destroy

  before_validation :downcase_status, :determine_level, :determine_chamber
  after_update :send_notifications_on_update

  validates :external_id, :category, :chamber, :introduced_date_time_utc, :level, :link, :status, :summary, :title, :sway_locale_id, :legislator_id, presence: {message: "can't be blank"}

  validates :external_id, uniqueness: {scope: :sway_locale_id, allow_nil: true}

  sig { params(sway_locale: SwayLocale).returns(Bill) }
  def self.of_the_week(sway_locale:)
    b = Bill.where(scheduled_release_date_utc: Time.zone.today, sway_locale:).first
    b.presence || Bill.where(sway_locale:).order(created_at: :asc).limit(1).first
  end

  class Status
    PASSED = "passed"
    FAILED = "failed"
    COMMITTEE = "committee"
    VETOED = "vetoed"
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

  sig { returns(T::Array[Organization]) }
  def organizations
    organization_bill_positions.map(&:organization)
  end

  # Render a single bill from a controller
  def render(current_user)
    {
      bill: to_builder.attributes!,
      positions: organization_bill_positions.map { |obp| obp.to_builder.attributes! },
      legislatorVotes: legislator_votes.map { |lv| lv.to_builder.attributes! },
      sponsor: legislator.to_builder.attributes!,
      userVote: UserVote.find_by(
        user: current_user,
        bill_id: id
      )&.attributes
    }
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

      b.scheduled_release_date_utc scheduled_release_date_utc

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

  # after initialize

  def determine_level
    return if level.present? || sway_locale.nil?

    self.level = if sway_locale.congress?
      "National"
    elsif sway_locale.region?
      "Regional"
    else
      "Local"
    end
  end

  def determine_chamber
    return if chamber.present? || sway_locale.nil?

    if sway_locale.congress? || sway_locale.region?
      # noop
    else
      self.chamber = "council"
    end
  end

  # before save

  sig { void }
  def downcase_status
    s = status
    return unless s

    if STATUSES.include?(s.downcase)
      self.status = s.downcase
    else
      Rails.logger.warn("Bill.downcase_status - received status of #{s} is NOT valid. Should be one of #{STATUSES.join(", ")}")
      self.status = nil
    end
  end

  # after create

  sig { void }
  def send_notifications_on_update
    Rails.logger.info("Bill.send_notifications_on_update - New Release Date - #{scheduled_release_date_utc} - WAS - #{attribute_before_last_save("scheduled_release_date_utc")}")
    if updated_scheduled_release_date_utc?
      SwayPushNotificationService.new(
        title: "New Bill of the Week",
        body: "#{title} in #{sway_locale.human_name}"
      ).send_push_notification
    end
  rescue Exception => e # rubocop:disable Lint/RescueException
    Rails.logger.error(e)
  end

  def updated_scheduled_release_date_utc?
    scheduled_release_date_utc == Time.zone.today && attribute_before_last_save("scheduled_release_date_utc") != Time.zone.today
  end
end
