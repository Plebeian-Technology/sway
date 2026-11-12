# frozen_string_literal: true

# @lat: [[bill-interesting-score-design#Why BillInterestingScoreCalculator is built this way]]
# @lat: [[bill-interesting-score#The bill interesting score#Signals follow published evidence]]
class BillInterestingScoreCalculator
  WEIGHT_VOTE_DEFECTION = 40.0
  WEIGHT_VOTE_ABSTENTION = 10.0
  WEIGHT_ORG_SPLIT = 40.0
  WEIGHT_TIMELINESS = 10.0
  WEIGHT_TESTIMONY_ENGAGEMENT = 50.0

  FULL_THEORETICAL_MAX = WEIGHT_VOTE_DEFECTION + WEIGHT_VOTE_ABSTENTION +
    WEIGHT_ORG_SPLIT + WEIGHT_TIMELINESS
  LOCAL_THEORETICAL_MAX = WEIGHT_ORG_SPLIT + WEIGHT_TIMELINESS +
    WEIGHT_TESTIMONY_ENGAGEMENT

  DEFECTION_MAGNITUDE_CAP = 8

  ABSTENTION_RATE_THRESHOLD = 0.10
  ABSTENTION_RATE_SATURATION = 0.40

  ORG_SPLIT_VOLUME_CAP = 8

  TESTIMONY_VOLUME_CAP = 50.0
  TESTIMONY_REPEAT_DISCOUNT = 0.20

  CLOSE_MARGIN_THRESHOLD = 0.10

  TIMELINESS_WINDOW_DAYS = 30

  # @lat: [[bill-interesting-score#The bill interesting score#Signals follow published evidence]]
  def self.theoretical_max(publishes_legislator_votes)
    publishes_legislator_votes ? FULL_THEORETICAL_MAX : LOCAL_THEORETICAL_MAX
  end

  def initialize(bill)
    @bill = bill
    @sway_locale = bill.sway_locale
  end

  def call
    org_for, org_against = org_position_counts
    # @lat: [[bill-interesting-score#The bill interesting score#Signals follow published evidence]]
    publishes_legislator_votes = @sway_locale.jurisdiction_rules.publishes_legislator_votes
    signals = publishes_legislator_votes ? full_signals(org_for, org_against) : local_signals(org_for, org_against)

    raw_score = signals.values_at(
      "vote_defection_score", "vote_abstention_score", "org_split_score", "timeliness_score", "testimony_engagement_score"
    ).compact.sum

    BillInterestingScore.create!(
      bill: @bill,
      raw_score: raw_score,
      normalized_score: raw_score / self.class.theoretical_max(publishes_legislator_votes),
      signals: signals,
      computed_at: Time.current
    )
  end

  private

  def local_signals(org_for, org_against)
    score, letters, individuals, groups, repeats = testimony_engagement_metrics

    {
      "vote_defection_score" => 0.0,
      "vote_abstention_score" => 0.0,
      "org_split_score" => org_split_score(org_for, org_against),
      "organization_split_score" => org_split_score(org_for, org_against),
      "timeliness_score" => timeliness_score,
      "testimony_engagement_score" => score,
      "testimony_letter_count" => letters,
      "testimony_individual_count" => individuals,
      "testimony_campaign_count" => groups,
      "testimony_repeat_count" => repeats,
      "real_for" => 0,
      "real_against" => 0,
      "real_abstain" => 0,
      "org_for" => org_for,
      "organization_for" => org_for,
      "org_against" => org_against,
      "organization_against" => org_against
    }
  end

  def testimony_engagement_metrics
    letter_count, repeat_letters, campaign_origin_letters, group_count = testimony_counts
    net_letters = [letter_count - repeat_letters, 0].max
    individual_letters = [net_letters - campaign_origin_letters, 0].max
    effective_volume = individual_letters + (campaign_origin_letters * TESTIMONY_REPEAT_DISCOUNT) + (group_count * 2.0)
    volume_factor = (effective_volume / TESTIMONY_VOLUME_CAP).clamp(0.0, 1.0)
    testimony_score = (volume_factor * WEIGHT_TESTIMONY_ENGAGEMENT).round(2).to_f

    [testimony_score, letter_count, individual_letters, group_count, repeat_letters]
  end

  def testimony_counts
    counts = @bill.bill_llm_provisioning&.cleaned_testimony&.dig("counts")
    if counts.is_a?(Hash) && counts["letter_count"].to_i > 0
      [
        counts["letter_count"].to_i,
        counts["repeat_letters"].to_i,
        counts["campaign_origin_letters"].to_i,
        counts["group_count"].to_i
      ]
    elsif @bill.campaigns.exists?
      c_letters = @bill.campaigns.sum(:letter_count).to_i
      c_senders = @bill.campaigns.sum(:sender_count).to_i
      c_groups = @bill.campaigns.count
      repeat = [c_letters - c_senders, 0].max
      [c_letters, repeat, c_letters, c_groups]
    elsif counts.is_a?(Hash)
      [
        counts["letter_count"].to_i,
        counts["repeat_letters"].to_i,
        counts["campaign_origin_letters"].to_i,
        counts["group_count"].to_i
      ]
    else
      [0, 0, 0, 0]
    end
  end

  def full_signals(org_for, org_against)
    real_votes = real_legislator_votes
    votes_by_bloc = group_votes_by_bloc(real_votes)
    real_for = real_votes.count { |v| v.support == LegislatorVote::Support::FOR }
    real_against = real_votes.count { |v| v.support == LegislatorVote::Support::AGAINST }
    real_abstain = real_votes.count { |v| v.support == LegislatorVote::Support::ABSTAIN }

    {
      "vote_defection_score" => defection_score(votes_by_bloc),
      "vote_abstention_score" => abstention_score(real_abstain, real_for + real_against + real_abstain),
      "org_split_score" => org_split_score(org_for, org_against),
      "organization_split_score" => org_split_score(org_for, org_against),
      "timeliness_score" => timeliness_score,
      "testimony_engagement_score" => 0.0,
      "testimony_letter_count" => 0,
      "testimony_individual_count" => 0,
      "testimony_campaign_count" => 0,
      "testimony_repeat_count" => 0,
      "real_for" => real_for,
      "real_against" => real_against,
      "real_abstain" => real_abstain,
      "org_for" => org_for,
      "organization_for" => org_for,
      "org_against" => org_against,
      "organization_against" => org_against
    }
  end

  def real_legislator_votes
    @bill.legislator_votes.where(inferred: false).includes(:legislator).to_a
  end

  def group_votes_by_bloc(votes)
    votes.each_with_object({}) do |vote, blocs|
      next if vote.support == LegislatorVote::Support::ABSTAIN

      bloc = (blocs[vote.legislator.party] ||= {for: 0, against: 0})
      bloc[:for] += 1 if vote.support == LegislatorVote::Support::FOR
      bloc[:against] += 1 if vote.support == LegislatorVote::Support::AGAINST
    end
  end

  def defection_score(votes_by_bloc)
    magnitude = votes_by_bloc.sum do |_party, counts|
      total = counts[:for] + counts[:against]
      (total < 2) ? 0 : [counts[:for], counts[:against]].min
    end
    [magnitude.to_f / DEFECTION_MAGNITUDE_CAP, 1.0].min * WEIGHT_VOTE_DEFECTION
  end

  def abstention_score(abstain_count, total_real_cast)
    return 0.0 if total_real_cast.zero?

    rate = abstain_count.to_f / total_real_cast
    return 0.0 if rate <= ABSTENTION_RATE_THRESHOLD

    fraction = [(rate - ABSTENTION_RATE_THRESHOLD) / (ABSTENTION_RATE_SATURATION - ABSTENTION_RATE_THRESHOLD), 1.0].min
    fraction * WEIGHT_VOTE_ABSTENTION
  end

  # @lat: [[bill-interesting-score#The bill interesting score#Signals follow published evidence]]
  def org_position_counts
    supports = OrganizationBillPosition
      .where(bill_id: @bill.id, active: true)
      .pluck(:support)
      .map { |support| OrganizationBillPosition.normalize_support(support) }
    [
      supports.count(LegislatorVote::Support::FOR),
      supports.count(LegislatorVote::Support::AGAINST)
    ]
  end

  def org_split_score(for_count, against_count)
    total = for_count + against_count
    return 0.0 if total < 2

    evenness = 1.0 - ((for_count - against_count).abs.to_f / total)
    volume_factor = [total.to_f / ORG_SPLIT_VOLUME_CAP, 1.0].min
    evenness * volume_factor * WEIGHT_ORG_SPLIT
  end

  # @lat: [[bill-interesting-score#The bill interesting score#Signals follow published evidence]]
  def timeliness_score
    most_recent = [
      @bill.introduced_date_time_utc,
      @bill.house_vote_date_time_utc,
      @bill.senate_vote_date_time_utc
    ].compact.max #: ActiveSupport::TimeWithZone?
    return 0.0 if most_recent.nil?

    days_ago = (Time.zone.now - most_recent) / 86_400.0
    fraction = (1.0 - (days_ago / TIMELINESS_WINDOW_DAYS)).clamp(0.0, 1.0)
    fraction * WEIGHT_TIMELINESS
  end
end
