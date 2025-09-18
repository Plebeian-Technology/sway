# frozen_string_literal: true
# typed: true

# == Schema Information
#
# Table name: users
#
#  id                       :integer          not null, primary key
#  current_sign_in_at       :datetime
#  current_sign_in_ip       :string
#  email                    :string
#  full_name                :string
#  is_admin                 :boolean          default(FALSE)
#  is_email_verified        :boolean
#  is_phone_verified        :boolean
#  is_registered_to_vote    :boolean
#  is_registration_complete :boolean
#  last_sign_in_at          :datetime
#  last_sign_in_ip          :string
#  phone                    :string
#  sign_in_count            :integer          default(0), not null
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  webauthn_id              :string
#
# Indexes
#
#  index_users_on_email        (email) UNIQUE
#  index_users_on_phone        (phone) UNIQUE
#  index_users_on_webauthn_id  (webauthn_id) UNIQUE
#
class User < ApplicationRecord
  extend T::Sig

  CREDENTIAL_MIN_AMOUNT = 1
  ADMIN_PHONES = ENV["ADMIN_PHONES"]&.split(",") || []
  API_USER_PHONES = ENV["API_USER_PHONES"]&.split(",") || []

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

      block_list =
        Rails
          .cache
          .fetch("email_blocklist") do
            File.read(Constants::DISPOSABLE_EMAIL_BLOCKLIST_FILE_PATH).split(
              "\n",
            ) + %w[simplelogin.com mozmail.com privaterelay.appleid.com]
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

  attr_accessor :webauthn_id

  has_one :user_address, dependent: :destroy
  has_one :address, through: :user_address
  has_many :user_districts, dependent: :destroy

  has_many :api_keys, as: :bearer, dependent: :destroy

  has_many :user_organization_memberships, dependent: :destroy
  has_many :organizations, through: :user_organization_memberships

  # Should only have 1 user_invite url, can change to has_many later if needed
  has_one :user_inviter, inverse_of: :user, dependent: :destroy
  has_one :api_key, inverse_of: :bearer, dependent: :destroy
  has_one :refresh_token, dependent: :destroy

  has_many :push_notification_subscriptions, dependent: :destroy

  has_many :passkeys, dependent: :destroy
  has_many :user_legislators, dependent: :destroy
  has_many :user_votes, dependent: :destroy

  validates :phone,
            presence: true,
            uniqueness: true,
            length: {
              minimum: 10,
              maximum: 10,
            }
  validates :email, email: true, uniqueness: { allow_nil: true }
  validates :full_name, format: { with: /\A[a-z ,.'-]+\z/i, allow_nil: true }

  after_initialize { self.webauthn_id ||= WebAuthn.generate_user_id }

  before_create do
    self.is_email_verified = false
    self.is_phone_verified = false
    self.is_registration_complete = false
    self.is_registered_to_vote = false
    self.is_admin = false

    self.sign_in_count = 0
  end

  before_save { self.phone = phone&.remove_non_digits }

  after_commit :create_user_invite_url

  # Returns an Array because users may have multiple SwayLocales
  # ex. city, state, congressional
  sig { returns(T::Array[SwayLocale]) }
  def sway_locales
    a = address
    a ? a.sway_locales : []
  end

  sig { returns(T.nilable(SwayLocale)) }
  def default_sway_locale
    sway_locales.find { |s| !s.congress? } || sway_locales.first
  end

  sig do
    params(sway_locale: T.nilable(SwayLocale)).returns(T::Array[UserLegislator])
  end
  def user_legislators_by_locale(sway_locale)
    user_legislators
      .where(active: true)
      .select { |ul| sway_locale.eql?(ul.legislator.district.sway_locale) }
  end

  sig do
    params(sway_locale: T.nilable(SwayLocale)).returns(T::Array[Legislator])
  end
  def legislators(sway_locale)
    user_legislators_by_locale(sway_locale).map(&:legislator)
  end

  sig { params(sway_locale: T.nilable(SwayLocale)).returns(T::Array[District]) }
  def districts(sway_locale)
    legislators(sway_locale).filter_map(&:district).uniq(&:id)
  end

  sig { returns(T::Boolean) }
  def email_sendable?
    !!is_email_verified && email.present?
  end

  def as_json(options = {})
    if is_sway_admin?
      super
    else
      super({ except: :is_admin }.merge(options))
    end
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |user|
      user.id id
      user.full_name full_name
      user.email email
      user.phone phone
      user.invite_url invite_url
      user.is_email_verified is_email_verified
      user.is_registration_complete is_registration_complete
      user.is_registered_to_vote is_registered_to_vote

      user.is_admin is_sway_admin? if is_sway_admin?
    end
  end

  sig { returns(T::Boolean) }
  def is_sway_admin?
    ADMIN_PHONES.include?(phone)
  end

  sig { returns(T::Boolean) }
  def is_sway_api_user?
    API_USER_PHONES.include?(phone)
  end

  sig { returns(T::Boolean) }
  def has_sway_passkey?
    passkeys.size.positive?
  end

  sig { returns(T::Boolean) }
  def can_delete_sway_passkeys?
    passkeys.size > CREDENTIAL_MIN_AMOUNT
  end

  sig { returns(T::Boolean) }
  def has_user_legislators?
    user_legislators.present?
  end

  sig { void }
  def create_user_invite_url
    # https://stackoverflow.com/questions/3861777/determine-what-attributes-were-changed-in-rails-after-save-callback
    return if user_inviter.present?

    UserInviter.from(user: self)
  end

  def invite_url
    user_inviter&.short_url
  end
end
