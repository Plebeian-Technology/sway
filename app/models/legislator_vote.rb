# frozen_string_literal: true
# typed: strict

# == Schema Information
#
# Table name: legislator_votes
#
#  id            :integer          not null, primary key
#  support       :string           not null
#  created_at    :datetime         not null
#  updated_at    :datetime         not null
#  bill_id       :integer          not null
#  legislator_id :integer          not null
#
# Indexes
#
#  index_legislator_votes_on_bill_id        (bill_id)
#  index_legislator_votes_on_legislator_id  (legislator_id)
#
# Foreign Keys
#
#  bill_id        (bill_id => bills.id)
#  legislator_id  (legislator_id => legislators.id)
#
class LegislatorVote < ApplicationRecord
    extend T::Sig

    class Support
        FOR = "FOR"
        AGAINST = "AGAINST"
        ABSTAIN = "ABSTAIN"

        FOR_AGAINST = T.let([FOR, AGAINST], T::Array[String])

        ALL = T.let([FOR, AGAINST, ABSTAIN], T::Array[String])
    end

    belongs_to :legislator
    belongs_to :bill

    after_initialize :transform_support_to_for_against_abstain, :upcase_support
    after_save_commit :update_scores
    # after_destroy_commit :update_scores # TODO: Update Scores if a Legislator Vote is destroyed

    validates :support, :bill_id, :legislator_id, presence: { message: "%<attribute>s can't be blank" }
    validates :support,
                        inclusion: {
                            in: [LegislatorVote::Support::FOR, LegislatorVote::Support::AGAINST, LegislatorVote::Support::ABSTAIN],
                        }

    sig { returns(Bill) }
    def bill
        T.cast(super, Bill)
    end

    sig { returns(Legislator) }
    def legislator
        T.cast(super, Legislator)
    end

    sig { returns(T::Boolean) }
    def for?
        support == LegislatorVote::Support::FOR
    end

    sig { returns(T::Boolean) }
    def against?
        support == LegislatorVote::Support::AGAINST
    end

    sig { returns(T::Boolean) }
    def abstain?
        support.present? && ![LegislatorVote::Support::FOR, LegislatorVote::Support::AGAINST].include?(support)
    end

    sig { returns(Jbuilder) }
    def to_builder
        Jbuilder.new do |lv|
            lv.id id
            lv.legislator_id legislator_id
            lv.bill_id bill_id
            lv.support support
        end
    end

    private

    sig { void }
    def upcase_support
        self.support = support.upcase.strip
    end

    sig { void }
    def transform_support_to_for_against_abstain
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
        else
            s
        end
    end

    sig { void }
    def update_scores
        OnLegislatorVoteUpdateScoresJob.perform_later(self, support_before_last_save)
    end
end
