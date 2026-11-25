# frozen_string_literal: true

# @lat: [[score-recompute-service-overview#Why recompute_bill_score_districts! counts DISTINCT user_votes.id]]
# @lat: [[scores-and-agreement#Scores are recomputed, never incremented]]
class ScoreRecomputeService
  CLASS_TO_COUNT_COLUMN = {
    agreed: :count_agreed,
    disagreed: :count_disagreed,
    no_legislator_vote: :count_no_legislator_vote,
    legislator_abstained: :count_legislator_abstained
  }.freeze

  class << self
    def recompute_bill!(bill)
      bill_score = BillScore.create_or_find_by!(bill: bill)

      support_counts = UserVote.where(bill_id: bill.id).group(:support).count
      bill_score.update!(
        {
          for: support_counts.fetch(LegislatorVote::Support::FOR, 0),
          against: support_counts.fetch(LegislatorVote::Support::AGAINST, 0)
        }
      )

      recompute_bill_score_districts!(bill, bill_score)
    end

    # @lat: [[score-recompute-service-overview#Why recompute_bill_score_districts! counts DISTINCT user_votes.id]]
    def recompute_legislator!(legislator_term)
      recompute_legislator_district!(legislator_term)
      recompute_legislator_locale!(legislator_term)
    end

    # @lat: [[score-recompute-service-overview#District score vs. locale score]]
    def recompute_legislator_district!(legislator_term)
      legislator = legislator_term.legislator
      district_user_ids =
        UserLegislator
          .where(legislator_id: legislator.id, active: true)
          .pluck(:user_id)
      LegislatorDistrictScore
        .create_or_find_by!(legislator_term: legislator_term)
        .update!(
          tally_group_agreement(
            district_user_ids,
            legislator_term,
            legislator.sway_locale,
            bill_ids_with_minimum_district_voters(legislator_term.district_id)
          )
        )
    end

    # @lat: [[score-updater-service-design#Why each score family uses a different scope and a different term]]
    def recompute_district_scores!(bill_ids, legislators: [])
      tallied_district_ids =
        BillScoreDistrict.joins(:bill_score).where(bill_scores: {bill_id: bill_ids}).select(:district_id)
      terms = LegislatorTerm.current.where(district_id: tallied_district_ids).includes(:legislator).to_a
      (legislators.filter_map(&:active_term) + terms).uniq(&:id).each do |legislator_term|
        recompute_legislator_district!(legislator_term)
      end
    end

    # @lat: [[score-recompute-service-overview#Why recompute_legislator_locale! reads the locale off the legislator, not through districts]]
    def recompute_legislator_locale!(legislator_term)
      legislator = legislator_term.legislator
      sway_locale = legislator.sway_locale
      locale_user_ids =
        User
          .joins(user_legislators: :legislator)
          .where(user_legislators: {active: true}, legislators: {sway_locale_id: sway_locale.id})
          .distinct
          .pluck(:id)
      LegislatorLocaleScore
        .create_or_find_by!(legislator_term: legislator_term)
        .update!(
          tally_group_agreement(
            locale_user_ids,
            legislator_term,
            sway_locale,
            bill_ids_with_minimum_voters(sway_locale)
          )
        )
    end

    # @lat: [[score-recompute-service-overview#Why recompute_bill_score_districts! counts DISTINCT user_votes.id]]
    # @lat: [[score-recompute-user-legislator-term-race#The race window this leaves, and why it is safe]]
    def recompute_user_legislator!(user_legislator, legislator_term)
      if user_legislator.is_a?(User)
        user_legislator = UserLegislator.find_by!(user: user_legislator, legislator_id: legislator_term.legislator_id)
      end

      UserLegislatorTermScore
        .find_or_create_by!(user_legislator: user_legislator, legislator_term: legislator_term)
        .update!(
          tally_agreement([user_legislator.user_id], legislator_term, legislator_term.sway_locale)
        )
    end

    def covering_term_for(vote_date, terms)
      return nil if vote_date.blank? || terms.empty?

      term = TermWindow.covering(vote_date, terms) #: LegislatorTerm?
      term = nil if term && TermWindow.ends_on(term) <= vote_date
      term
    end

    # @lat: [[score-recompute-service-overview#Why recompute_bill_score_districts! counts DISTINCT user_votes.id]]
    # @lat: [[scores-and-agreement#Abstention is not disagreement]]
    def classify(user_support, legislator_support)
      return :no_legislator_vote if legislator_support.blank?
      return :legislator_abstained if legislator_support == LegislatorVote::Support::ABSTAIN

      (user_support == legislator_support) ? :agreed : :disagreed
    end

    private

    def recompute_bill_score_districts!(bill, bill_score)
      # @lat: [[score-recompute-service-overview#Why recompute_bill_score_districts! counts DISTINCT user_votes.id]]
      district_counts =
        UserVote
          .where(bill_id: bill.id)
          .joins(user: {user_legislators: {legislator: :district}})
          .where(
            user_legislators: {active: true},
            districts: {sway_locale_id: bill.sway_locale_id}
          )
          .group("districts.id", "user_votes.support")
          .distinct
          .count("user_votes.id")

      per_district = {}
      district_counts.each do |(district_id, support), count|
        bucket = (per_district[district_id] ||= {for: 0, against: 0})
        if support == LegislatorVote::Support::FOR
          bucket[:for] = count
        elsif support == LegislatorVote::Support::AGAINST
          bucket[:against] = count
        end
      end

      per_district.each do |district_id, tally|
        BillScoreDistrict
          .create_or_find_by!(bill_score: bill_score, district_id: district_id)
          .update!({for: tally[:for], against: tally[:against]})
      end

      # @lat: [[scores-and-agreement#Scores are recomputed, never incremented]]
      bill_score
        .bill_score_districts
        .where.not(district_id: per_district.keys)
        .update_all({for: 0, against: 0})
    end

    # @lat: [[score-recompute-service-overview#Why recompute_bill_score_districts! counts DISTINCT user_votes.id]]
    def tally_agreement(user_ids, legislator_term, sway_locale)
      count_by_class(counted_pairs(user_ids, legislator_term, sway_locale))
    end

    # @lat: [[voter-privacy-threshold#Legislator scores count only bills that reached the minimum]]
    def tally_group_agreement(user_ids, legislator_term, sway_locale, bill_ids_with_minimum_voters)
      pairs =
        counted_pairs(user_ids, legislator_term, sway_locale)
          .select { |_user_id, _user_support, _legislator_support, bill_id| bill_ids_with_minimum_voters.include?(bill_id) }
      count_by_class(pairs).merge(distinct_voter_count: pairs.map(&:first).uniq.size)
    end

    def bill_ids_with_minimum_voters(sway_locale)
      BillScore
        .joins(:bill)
        .where(bills: {sway_locale_id: sway_locale.id})
        .where('bill_scores."for" + bill_scores."against" >= ?', VoteComparisonPrivacy::MINIMUM_VOTERS)
        .pluck(:bill_id)
        .to_set
    end

    # @lat: [[voter-privacy-threshold#Legislator scores count only bills that reached the minimum]]
    def bill_ids_with_minimum_district_voters(district_id)
      tallied =
        BillScoreDistrict
          .where(district_id: district_id)
          .where('bill_score_districts."for" + bill_score_districts."against" >= ?', VoteComparisonPrivacy::MINIMUM_VOTERS)
          .select(:bill_score_id)
      BillScore
        .where(id: tallied)
        .includes(bill_score_districts: :district)
        .select { |bill_score| bill_score.countable_district_ids.include?(district_id) }
        .to_set(&:bill_id)
    end

    def count_by_class(pairs)
      counts = {
        count_agreed: 0,
        count_disagreed: 0,
        count_no_legislator_vote: 0,
        count_legislator_abstained: 0
      }
      pairs.each do |_user_id, user_support, legislator_support, _bill_id|
        counts[CLASS_TO_COUNT_COLUMN.fetch(classify(user_support, legislator_support))] += 1
      end
      counts
    end

    # Rows of [user_id, user_support, legislator_support, bill_id] inside the term's window.
    def counted_pairs(user_ids, legislator_term, sway_locale)
      legislator = legislator_term.legislator

      rows =
        UserVote
          .joins(:bill)
          .where(user_id: user_ids, bills: {sway_locale_id: sway_locale.id})
          .joins(
            # @lat: [[score-recompute-service-overview#Counting agreement: tally_agreement]]
            "LEFT JOIN legislator_votes ON legislator_votes.bill_id = user_votes.bill_id " \
              "AND legislator_votes.legislator_id = #{legislator.id.to_i}"
          )
          .pluck(
            "user_votes.user_id",
            "user_votes.support",
            "legislator_votes.support",
            "user_votes.bill_id"
          )

      bill_ids = rows.pluck(3).uniq
      bills = Bill.where(id: bill_ids).includes(:legislative_session)
      term_begins_on = TermWindow.begins_on(legislator_term)
      term_ends_on = TermWindow.ends_on(legislator_term)
      terms = legislator.legislator_terms.includes(district: :sway_locale).to_a

      valid_bill_ids = Set.new
      bills.each do |bill|
        intro_time = bill.introduced_date_time_utc
        next unless intro_time

        intro_date = intro_time.to_date
        next if intro_date < term_begins_on || intro_date > term_ends_on

        if (session = bill.legislative_session)
          next if intro_date < session.start_date || intro_date > session.end_date
        end

        anchor_time = bill.house_vote_date_time_utc || bill.senate_vote_date_time_utc || intro_time
        next unless covering_term_for(intro_time, terms) == legislator_term ||
          covering_term_for(anchor_time, terms) == legislator_term

        valid_bill_ids << bill.id
      end

      rows.select { |_user_id, _user_support, _legislator_support, bill_id| valid_bill_ids.include?(bill_id) }
    end
  end
end
