# typed: true

# == Schema Information
#
# Table name: users
#
#  id                       :integer          not null, primary key
#  email                    :string
#  is_email_verified        :boolean
#  phone                    :string
#  is_phone_verified        :boolean
#  is_registration_complete :boolean
#  is_registered_to_vote    :boolean
#  is_admin                 :boolean          default(FALSE)
#  webauthn_id              :string
#  sign_in_count            :integer          default(0), not null
#  current_sign_in_at       :datetime
#  last_sign_in_at          :datetime
#  current_sign_in_ip       :string
#  last_sign_in_ip          :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
class User < ApplicationRecord
  extend T::Sig

  CREDENTIAL_MIN_AMOUNT = 1

  attr_accessor :webauthn_id

  has_one :user_address, dependent: :destroy
  has_one :address, through: :user_address
  has_many :passkeys, dependent: :destroy
  has_many :user_legislators, dependent: :destroy

  validates :phone, presence: true, uniqueness: true
  validates :email, uniqueness: true

  after_initialize do
    self.webauthn_id ||= WebAuthn.generate_user_id
  end

  before_create do
    self.is_email_verified = false
    self.is_phone_verified = false
    self.is_registration_complete = false
    self.is_registered_to_vote = false
    self.is_admin = false

    self.sign_in_count = 0
  end

  before_save do
    self.phone = phone&.remove_non_digits
  end

  # TODO: Returns an Array because users may have multiple SwayLocales
  # ex. city, state, congressional
  sig { returns(T::Array[SwayLocale]) }
  def sway_locales
    a = address
    a ? a.sway_locales : []
  end

  sig { returns(T.nilable(SwayLocale)) }
  def default_sway_locale
    sway_locales.filter { |s| !s.is_congress?}.first || sway_locales.first
  end

  sig { params(sway_locale: SwayLocale).returns(T::Array[UserLegislator]) }
  def user_legislators_by_locale(sway_locale)
    user_legislators.filter_map do |ul|
      ul if sway_locale.eql?(ul.legislator.district.sway_locale)
    end
  end

  sig { params(sway_locale: SwayLocale).returns(T::Array[Legislator]) }
  def legislators(sway_locale)
    user_legislators_by_locale(sway_locale).map(&:legislator)
  end

  sig { params(sway_locale: SwayLocale).returns(T::Array[District]) }
  def districts(sway_locale)
    legislators(sway_locale).filter_map(&:district).uniq(&:id)
  end

  sig { returns(Jbuilder) }
  def to_builder
    Jbuilder.new do |user|
      user.id id
      user.email email
      user.phone phone
      user.is_registration_complete is_registration_complete
      user.is_registered_to_vote is_registered_to_vote
      user.is_admin SwayRails::ADMIN_PHONES.include?(phone)
    end
  end

  sig { returns(T::Boolean) }
  def can_delete_passkeys?
    passkeys.size > CREDENTIAL_MIN_AMOUNT
  end

  sig { returns(T::Boolean) }
  def has_user_legislators?
    user_legislators.present?
  end
end
