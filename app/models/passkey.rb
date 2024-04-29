# typed: strict
# frozen_string_literal: true

# == Schema Information
#
# Table name: passkeys
#
#  id           :integer          not null, primary key
#  user_id      :integer          not null
#  label        :string           not null
#  external_id  :string
#  public_key   :string
#  sign_count   :integer
#  last_used_at :datetime
#  created_at   :datetime         not null
#  updated_at   :datetime         not null
#
class Passkey < ApplicationRecord
  belongs_to :user

  validates :external_id, :public_key, :label, :sign_count, presence: true
  validates :external_id, uniqueness: true
  validates :sign_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0, less_than_or_equal_to: 2**32 - 1 }
end
