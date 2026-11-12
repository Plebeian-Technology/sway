# frozen_string_literal: true

# == Schema Information
#
# Table name: legislator_votes
# Database name: primary
#
#  id                 :integer          not null, primary key
#  inferred           :boolean          default(FALSE), not null
#  source             :string           not null
#  support            :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  bill_id            :integer          not null
#  legislator_id      :integer          not null
#  legislator_term_id :integer          not null
#
# Indexes
#
#  index_legislator_votes_on_bill_and_person_null_term_unique  (bill_id,legislator_id) UNIQUE WHERE legislator_term_id IS NULL
#  index_legislator_votes_on_bill_and_term_unique              (bill_id,legislator_term_id) UNIQUE WHERE legislator_term_id IS NOT NULL
#  index_legislator_votes_on_bill_id                           (bill_id)
#  index_legislator_votes_on_legislator_id                     (legislator_id)
#  index_legislator_votes_on_legislator_term_id                (legislator_term_id)
#
# Foreign Keys
#
#  bill_id             (bill_id => bills.id)
#  legislator_id       (legislator_id => legislators.id)
#  legislator_term_id  (legislator_term_id => legislator_terms.id)
#
class LegislatorVote < ApplicationRecord
  # @lat: [[naming-decisions#Two vocabularies, one per actor]]
  class Support
    FOR = "FOR"
    AGAINST = "AGAINST"
    ABSTAIN = "ABSTAIN"

    FOR_AGAINST = [FOR, AGAINST].freeze

    ALL = [FOR, AGAINST, ABSTAIN].freeze
  end

  SOURCES = %w[manual congress open_states legistar generic].freeze

  belongs_to :legislator
  belongs_to :bill

  before_validation :transform_support_to_for_against_abstain, :upcase_support

  # @lat: [[bill-score-recompute-callback-split#LegislatorVote's bare after_commit callbacks]]
  after_commit :update_scores

  # @lat: [[bill-score-recompute-callback-split#LegislatorVote's bare after_commit callbacks]]
  after_commit :enqueue_interesting_score_recompute

  after_commit :broadcast_feed_update, on: %i[create update]

  validates :support,
    :bill_id,
    :legislator_id,
    presence: {
      message: "%<attribute>s can't be blank"
    }
  validates :support,
    inclusion: {
      in: [
        LegislatorVote::Support::FOR,
        LegislatorVote::Support::AGAINST,
        LegislatorVote::Support::ABSTAIN
      ]
    }
  validates :source,
    presence: {
      message: "%<attribute>s can't be blank"
    },
    inclusion: {
      in: SOURCES
    }

  def for?
    support == LegislatorVote::Support::FOR
  end

  def against?
    support == LegislatorVote::Support::AGAINST
  end

  def abstain?
    support == LegislatorVote::Support::ABSTAIN
  end

  def to_builder
    Jbuilder.new do |lv|
      lv.id id
      lv.legislator_id legislator_id
      lv.bill_id bill_id
      lv.support support
    end
  end

  private

  def upcase_support
    return if support.blank?

    self.support = support.upcase.strip
  end

  def transform_support_to_for_against_abstain
    return if support.blank?

    s = support.downcase
    case s
    when "yea"
      self.support = LegislatorVote::Support::FOR
    when "yes"
      self.support = LegislatorVote::Support::FOR
    when "aye"
      self.support = LegislatorVote::Support::FOR
    when "nay"
      self.support = LegislatorVote::Support::AGAINST
    when "no"
      self.support = LegislatorVote::Support::AGAINST
    when "not voting"
      self.support = LegislatorVote::Support::ABSTAIN
    when "present"
      self.support = LegislatorVote::Support::ABSTAIN
      # @lat: [[bill-score-recompute-callback-split#Why transform_support_to_for_against_abstain has no else arm]]
    end
  end

  def update_scores
    # @lat: [[bill-score-recompute-callback-split#LegislatorVote's bare after_commit callbacks]]
    return if !destroyed? && !saved_change_to_support?

    OnLegislatorVoteUpdateScoresJob.perform_later(legislator_id, legislator_term_id)
  end

  # @lat: [[bill-score-recompute-callback-split#LegislatorVote's bare after_commit callbacks]]
  def enqueue_interesting_score_recompute
    RecomputeBillInterestingScoreJob.perform_later(bill_id)
  end

  def broadcast_feed_update
    became_visible = (previously_new_record? && !inferred?) || saved_change_to_inferred?(from: true, to: false)
    return unless became_visible

    user_ids = UserLegislator.active.where(legislator_id: legislator_id).distinct.pluck(:user_id)
    return if user_ids.empty?

    FeedUpdateBroadcastJob.perform_later(user_ids)
  end
end
