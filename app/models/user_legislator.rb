# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: user_legislators
#
#  id            :integer          not null, primary key
#  active        :boolean          default(TRUE), not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  legislator_id :integer          not null
#  user_id       :integer          not null
#
# Indexes
#
#  by_unique_user_and_legislator            (user_id,legislator_id) UNIQUE WHERE created_at >= 2025-02-24
#  index_user_legislators_on_legislator_id  (legislator_id)
#  index_user_legislators_on_user_id        (user_id)
#
# Foreign Keys
#
#  legislator_id  (legislator_id => legislators.id)
#  user_id        (user_id => users.id)
#
class UserLegislator < ApplicationRecord
  extend T::Sig

  belongs_to :legislator
  belongs_to :user

  has_one :user_legislator_score, dependent: :destroy
  has_many :user_legislator_emails, dependent: :destroy

  after_create_commit :create_user_legislator_score

  sig { returns(Legislator) }
  def legislator
    T.cast(super, Legislator)
  end

  private

  sig { returns(UserLegislatorScore) }
  def create_user_legislator_score
    UserLegislatorScore.create(user_legislator: self)
  end
end
