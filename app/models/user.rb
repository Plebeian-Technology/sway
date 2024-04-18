# == Schema Information
#
# Table name: users
#
#  id                       :bigint           not null, primary key
#  email                    :string
#  is_email_verified        :boolean
#  phone                    :string
#  is_phone_verified        :boolean
#  is_registration_complete :boolean
#  is_registered_to_vote    :boolean
#  is_admin                 :boolean          default(FALSE)
#  last_login_utc           :datetime
#  address_id               :bigint
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable, :passkey_authenticatable

  belongs_to :address, required: false

  has_many :passkeys, dependent: :destroy

  def self.passkeys_class
    Passkey
  end

  def self.find_for_passkey(passkey)
    find_by(id: passkey.user.id)
  end

  def after_passkey_authentication(passkey:)
  end

  protected

  def password_required?
    false
  end
end

Devise.add_module :passkey_authenticatable,
                  model: 'devise/passkeys/model',
                  route: {session: [nil, :new, :create, :destroy] },
                  controller: 'controller/sessions',
                  strategy: true
