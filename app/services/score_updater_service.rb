# frozen_string_literal: true

# @lat: [[score-updater-service-design#Why broadcast_score_refresh is a public class method]]
class ScoreUpdaterService
  class << self
    # @lat: [[score-updater-service-design#Why broadcast_score_refresh is a public class method]]
    def broadcast_score_refresh(user)
      ActionCable.server.broadcast(
        "scores_#{user.id}",
        {action: "refresh_scores"}
      )
    rescue StandardError, LoadError => e
      SwayLogging.log_exception("score_updater.broadcast_failed", exception: e, user_id: user.id)
    end
  end

  def initialize(user_vote)
    @user_vote = user_vote

    @user = nil
    @bill = nil
    @sway_locale = nil

    SwayLogging.info(
      "ScoreUpdaterService.new - initialized service with UserVote - #{user_vote.id}"
    )
  end

  def call
    ApplicationRecord.transaction(requires_new: true) do
      # @lat: [[bill-session-archiving#Bill session archiving#Ingestion and pending work]]
      return unless Bill.exists?(@user_vote.bill_id)

      ScoreRecomputeService.recompute_bill!(bill)
      # @lat: [[score-updater-service-design#Why each score family uses a different scope and a different term]]
      user.user_legislators_by_locale(sway_locale).each do |user_legislator|
        terms = user_legislator.legislator.legislator_terms.includes(district: :sway_locale).to_a
        next if terms.empty?

        covering_terms =
          [bill_anchor_date, bill.introduced_date_time_utc]
            .compact
            .filter_map { |date| ScoreRecomputeService.covering_term_for(date, terms) }
            .uniq(&:id)

        covering_terms.each do |legislator_term|
          ScoreRecomputeService.recompute_user_legislator!(user_legislator, legislator_term)
        end
      end
      # @lat: [[score-updater-service-design#Why each score family uses a different scope and a different term]]
      ScoreRecomputeService.recompute_district_scores!([bill.id], legislators: user.legislators(sway_locale))
      # @lat: [[score-updater-service-design#Why each score family uses a different scope and a different term]]
      eligible_bill_ids = ScoreRecomputeService.bill_ids_with_minimum_voters(sway_locale)
      sway_locale.legislators.each do |legislator|
        legislator_term = legislator.active_term
        next if legislator_term.nil?

        ScoreRecomputeService.recompute_legislator_locale!(legislator_term, eligible_bill_ids:)
      end
    end

    # @lat: [[score-updater-service-design#Why broadcast_score_refresh is a public class method]]
    broadcast_score_refresh
  end

  private

  def user
    @user ||= @user_vote.user
  end

  def bill
    @bill ||= @user_vote.bill
  end

  def sway_locale
    @sway_locale ||= bill.sway_locale
  end

  # @lat: [[scores-and-agreement#Every score is bound to a term]]
  def bill_anchor_date
    bill.house_vote_date_time_utc || bill.senate_vote_date_time_utc || bill.introduced_date_time_utc
  end

  def broadcast_score_refresh
    self.class.broadcast_score_refresh(user)
  end
end
