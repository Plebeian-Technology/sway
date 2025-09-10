# typed: strict

class OnLegislatorVoteUpdateScoresJob < ApplicationJob
    extend T::Sig

    queue_as :background

    # NOTE: newly_saved_legislator_vote.support should ALWAYS != previous_support
    sig { params(newly_saved_legislator_vote: LegislatorVote, previous_support: T.nilable(String)).void }
    def perform(newly_saved_legislator_vote, previous_support)
        if newly_saved_legislator_vote.support == previous_support
            Rails.logger.warn(
                "OnLegislatorVoteUpdateScoresJob.update_user_legislator_scores - SHOULD NOT BE TRIGGERED. newly_saved_legislator_vote.suport should NEVER == previous_support. LegislatorVote: #{newly_saved_legislator_vote.id}, previous_support: #{previous_support}",
            )
            return
        else
            Rails.logger.debug(
                "OnLegislatorVoteUpdateScoresJob.update_user_legislator_scores - LegislatorVote.new_support: #{newly_saved_legislator_vote.support}, previous_support: #{previous_support}",
            )
        end

        legislator = newly_saved_legislator_vote.legislator
        newly_saved_legislator_vote.bill

        users = UserLegislator.includes(:user).where(legislator:).map(&:user).compact

        update_legislator_district_score(newly_saved_legislator_vote, users, previous_support)
        update_user_legislator_scores(newly_saved_legislator_vote, users, previous_support)
    end

    sig { params(legislator_vote: LegislatorVote, users: T::Array[User], previous_support: T.nilable(String)).void }
    def update_legislator_district_score(legislator_vote, users, previous_support)
        legislator_district_score = LegislatorDistrictScore.find_or_create_by!(legislator: legislator_vote.legislator)

        bill_user_votes = UserVote.where(user: users, bill: legislator_vote.bill)

        current_count_agreed = bill_user_votes.count { |buv| buv.support == previous_support }
        current_count_disagreed =
            bill_user_votes.count do |buv|
                LegislatorVote::Support::FOR_AGAINST.include?(previous_support) && buv.support != previous_support
            end
        current_count_legislator_abstained = previous_support == LegislatorVote::Support::ABSTAIN ? bill_user_votes.size : 0
        current_count_no_legislator_vote = previous_support.blank? ? bill_user_votes.size : 0

        new_count_agreed = bill_user_votes.count { |buv| buv.support == legislator_vote.support }
        new_count_disagreed =
            bill_user_votes.count do |buv|
                LegislatorVote::Support::FOR_AGAINST.include?(legislator_vote.support) && buv.support != legislator_vote.support
            end
        new_count_legislator_abstained =
            legislator_vote.support == LegislatorVote::Support::ABSTAIN ? bill_user_votes.size : 0
        new_count_no_legislator_vote = legislator_vote.support.blank? ? bill_user_votes.size : 0

        diff_count_agreed = current_count_agreed + (new_count_agreed - current_count_agreed)
        diff_count_disagreed = current_count_disagreed + (new_count_disagreed - current_count_disagreed)
        diff_count_legislator_abstained =
            current_count_legislator_abstained + (new_count_legislator_abstained - current_count_legislator_abstained)
        diff_count_no_legislator_vote =
            current_count_no_legislator_vote + (new_count_no_legislator_vote - current_count_no_legislator_vote)

        Rails.logger.debug("LegislatorDistrictScore: #{legislator_district_score.id} BEFORE Update:")
        Rails.logger.debug(
            JSON.pretty_generate(
                {
                    count_agreed: current_count_agreed,
                    count_disagreed: current_count_disagreed,
                    count_legislator_abstained: current_count_legislator_abstained,
                    count_no_legislator_vote: current_count_no_legislator_vote,
                },
            ),
        )

        legislator_district_score.count_agreed = new_count_agreed
        legislator_district_score.count_disagreed = new_count_disagreed
        legislator_district_score.count_legislator_abstained = new_count_legislator_abstained
        legislator_district_score.count_no_legislator_vote = new_count_no_legislator_vote

        Rails.logger.debug("LegislatorDistrictScore: #{legislator_district_score.id} AFTER Update:")
        Rails.logger.debug(
            JSON.pretty_generate(
                {
                    count_agreed: diff_count_agreed,
                    count_disagreed: diff_count_disagreed,
                    count_legislator_abstained: diff_count_legislator_abstained,
                    count_no_legislator_vote: diff_count_no_legislator_vote,
                },
            ),
        )

        legislator_district_score.save!
    end

    sig { params(legislator_vote: LegislatorVote, users: T::Array[User], previous_support: T.nilable(String)).void }
    def update_user_legislator_scores(legislator_vote, users, previous_support)
        bill = legislator_vote.bill

        user_legislator_scores =
            T.cast(
                UserLegislator.where(user: users, legislator: legislator_vote.legislator).map(&:user_legislator_score),
                T::Array[UserLegislatorScore],
            ).compact
        user_votes = UserVote.where(user: users, bill:)

        user_legislator_scores.each do |uls|
            user_vote = user_votes.find { |uv| uv.user.id == uls.user_legislator.user_id }
            next if user_vote.nil?

            new_count_agreed = uls.count_agreed
            new_count_disagreed = uls.count_disagreed
            new_count_legislator_abstained = uls.count_legislator_abstained
            new_count_no_legislator_vote = uls.count_no_legislator_vote

            if previous_support.blank?
                new_count_no_legislator_vote -= 1 if uls.count_no_legislator_vote.positive?

                if legislator_vote.support == user_vote.support
                    new_count_agreed += 1
                elsif LegislatorVote::Support::FOR_AGAINST.include?(legislator_vote.support) &&
                            legislator_vote.support != user_vote.support
                    new_count_disagreed += 1
                elsif legislator_vote.support == LegislatorVote::Support::ABSTAIN
                    new_count_legislator_abstained += 1
                end
            elsif previous_support == LegislatorVote::Support::ABSTAIN
                new_count_legislator_abstained -= 1

                if legislator_vote.support == user_vote.support
                    new_count_agreed += 1
                elsif legislator_vote.support != user_vote.support
                    new_count_disagreed += 1
                end
            elsif user_vote.support == previous_support
                if legislator_vote.support == LegislatorVote::Support::ABSTAIN
                    new_count_legislator_abstained += 1
                elsif legislator_vote.support == user_vote.support
                    Rails.logger.warn(
                        "OnLegislatorVoteUpdateScoresJob.update_user_legislator_scores - SHOULD NOT BE TRIGGERED. user_vote.support == previous_support",
                    )
                    new_count_agreed += 1
                elsif legislator_vote.support != user_vote.support
                    new_count_disagreed += 1
                end

                new_count_agreed -= 1
            elsif user_vote.support != previous_support
                if legislator_vote.support == LegislatorVote::Support::ABSTAIN
                    new_count_legislator_abstained += 1
                elsif legislator_vote.support == user_vote.support
                    new_count_agreed += 1
                elsif legislator_vote.support != user_vote.support
                    Rails.logger.warn(
                        "OnLegislatorVoteUpdateScoresJob.update_user_legislator_scores - SHOULD NOT BE TRIGGERED. user_vote.support != previous_support",
                    )
                    new_count_disagreed += 1
                end

                # This plus legislator_vote.support != user_vote.support would == 0, however, this is (probably)
                # an impossible situation
                new_count_disagreed -= 1
            end

            Rails.logger.debug("UserLegislatorScore: #{uls.id} BEFORE Update:")
            Rails.logger.debug(
                JSON.pretty_generate(
                    {
                        count_agreed: uls.count_agreed,
                        count_disagreed: uls.count_disagreed,
                        count_legislator_abstained: uls.count_legislator_abstained,
                        count_no_legislator_vote: uls.count_no_legislator_vote,
                    },
                ),
            )

            uls.count_agreed = new_count_agreed
            uls.count_disagreed = new_count_disagreed
            uls.count_legislator_abstained = new_count_legislator_abstained
            uls.count_no_legislator_vote = new_count_no_legislator_vote

            Rails.logger.debug("UserLegislatorScore: #{uls.id} AFTER Update:")
            Rails.logger.debug(
                JSON.pretty_generate(
                    {
                        count_agreed: uls.count_agreed,
                        count_disagreed: uls.count_disagreed,
                        count_legislator_abstained: uls.count_legislator_abstained,
                        count_no_legislator_vote: uls.count_no_legislator_vote,
                    },
                ),
            )

            uls.save!
        end
    end
end
