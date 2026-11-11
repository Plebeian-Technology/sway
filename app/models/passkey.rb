# frozen_string_literal: true

# == Schema Information
#
# Table name: passkeys
# Database name: primary
#
#  id           :integer          not null, primary key
#  aaguid       :string
#  label        :string           not null
#  last_used_at :datetime
#  public_key   :string
#  sign_count   :integer
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#  external_id  :string
#  user_id      :integer          not null
#
# Indexes
#
#  index_passkeys_on_external_id        (external_id) UNIQUE
#  index_passkeys_on_public_key         (public_key) UNIQUE
#  index_passkeys_on_user_id            (user_id)
#  index_passkeys_on_user_id_and_label  (user_id,label) UNIQUE
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, :public_key, :label, :sign_count, presence: true
  validates :external_id, uniqueness: true
  # @lat: [[passkey-management-page-overview#Why label uniqueness is a model validation, not just a DB index]]
  validates :label, uniqueness: {scope: :user_id}
  validates :sign_count,
    numericality: {
      only_integer: true,
      greater_than_or_equal_to: 0,
      less_than_or_equal_to: 2**32 - 1
    }

  # @lat: [[passkey-aaguid-registry#Why some saved passkeys can never resolve to a name]]
  def device_name
    PasskeyAaguidRegistry.friendly_name(aaguid)
  end
end
