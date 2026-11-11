# frozen_string_literal: true

# == Schema Information
#
# Table name: user_legislators
# Database name: primary
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
#  by_unique_user_and_legislator            (user_id,legislator_id) UNIQUE
#  index_user_legislators_on_legislator_id  (legislator_id)
#
# Foreign Keys
#
#  legislator_id  (legislator_id => legislators.id)
#  user_id        (user_id => users.id)
#
class UserLegislator < ApplicationRecord
  belongs_to :legislator
  belongs_to :user

  scope :active, -> { where(active: true) }

  has_many :user_legislator_emails, dependent: :destroy

  # @lat: [[score-recompute-service-overview#Why recompute_bill_score_districts! counts DISTINCT user_votes.id]]
  has_many :user_legislator_term_scores, dependent: :destroy
end
