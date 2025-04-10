# typed: strict
# frozen_string_literal: true

# == Schema Information
#
# Table name: passkeys
#
#  id           :integer          not null, primary key
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
#  index_passkeys_on_external_id  (external_id) UNIQUE
#  index_passkeys_on_public_key   (public_key) UNIQUE
#  index_passkeys_on_user_id      (user_id)
#
# Foreign Keys
#
#  user_id  (user_id => users.id)
#
class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, :public_key, :label, :sign_count, presence: true
  validates :external_id, uniqueness: true
  validates :sign_count,
    numericality: {only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 2**32 - 1}
end
