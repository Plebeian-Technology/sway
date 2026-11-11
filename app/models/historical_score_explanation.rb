# frozen_string_literal: true

# @lat: [[current-legislator-term#Which term a legislator is serving now#Planned automatic legislator updates#Historical repair explanations]]
# == Schema Information
#
# Table name: historical_score_explanations
# Database name: primary
#
#  id                             :integer          not null, primary key
#  after_score                    :float
#  before_score                   :float
#  bills_summary                  :json             not null
#  body                           :text             not null
#  delta                          :float
#  dismissed_at                   :datetime
#  notified_at                    :datetime
#  score_type                     :string           not null
#  title                          :string           not null
#  created_at                     :datetime         not null
#  updated_at                     :datetime         not null
#  historical_repair_candidate_id :integer
#  historical_repair_preview_id   :integer
#  legislator_id                  :integer
#  user_id                        :integer          not null
#
# Indexes
#
#  idx_on_historical_repair_candidate_id_1ccbc7ca7a      (historical_repair_candidate_id)
#  idx_on_historical_repair_preview_id_106ec7dd1c        (historical_repair_preview_id)
#  index_historical_score_explanations_on_legislator_id  (legislator_id)
#  index_historical_score_explanations_on_user_id        (user_id)
#  index_score_explanations_on_user_and_created          (user_id,created_at)
#  index_score_explanations_on_user_and_dismissed        (user_id,dismissed_at)
#
# Foreign Keys
#
#  historical_repair_candidate_id  (historical_repair_candidate_id => historical_repair_candidates.id)
#  historical_repair_preview_id    (historical_repair_preview_id => historical_repair_previews.id)
#  legislator_id                   (legislator_id => legislators.id)
#  user_id                         (user_id => users.id)
#
class HistoricalScoreExplanation < ApplicationRecord
  belongs_to :user
  belongs_to :legislator, optional: true
  belongs_to :historical_repair_candidate, optional: true
  belongs_to :historical_repair_preview, optional: true

  validates :score_type, presence: true
  validates :title, presence: true
  validates :body, presence: true
end
