# frozen_string_literal: true

class ScoreUpdaterService
  def initialize(user_vote)
    @user_vote = user_vote

    @user = nil
    @bill = nil
    @sway_locale = nil

    @districts = nil
    @bill_districts = nil
    @user_districts = nil

    Rails.logger.info(
      "ScoreUpdaterService.new - initialized service with UserVote - #{user_vote.id}",
    )
  end

  def run
    update_bill_score_districts(update_bill_score)
    update_legislator_district_score
    update_user_legislator_scores

    broadcast_score_refresh
  end

  private

  def update_bill_score
    BillScore.find_or_create_by(bill:).update_score(@user_vote)
  end

  def update_bill_score_districts(bill_score)
    districts.map do |district|
      BillScoreDistrict.find_or_create_by!(district:, bill_score:).update_score(
        @user_vote,
      )
    end
  end

  def update_legislator_district_score
    user
      .legislators(sway_locale)
      .map do |l|
        LegislatorDistrictScore.find_or_create_by!(legislator: l).update_score(
          @user_vote,
        )
      end
  end

  def update_user_legislator_scores
    user
      .user_legislators_by_locale(sway_locale)
      .map do |ul|
        UserLegislatorScore.find_or_create_by!(
          user_legislator: ul,
        ).update_score(@user_vote)
      end
  end

  def districts
    @districts ||= bill_districts.select { |d| user_districts.include?(d) }
  end

  def bill_districts
    @bill_districts ||= sway_locale.districts.to_a
  end

  def user_districts
    @user_districts ||= user.districts(sway_locale)
  end

  def user
    @user ||= @user_vote.user
  end

  def bill
    @bill ||= @user_vote.bill
  end

  def sway_locale
    @sway_locale ||= bill.sway_locale
  end

  def broadcast_score_refresh
    ActionCable.server.broadcast(
      "scores_#{user.id}",
      { action: "refresh_scores" },
    )
  rescue StandardError, LoadError => e
    Rails.logger.error(
      "Failed broadcasting score refresh for user=#{user.id}: #{e.class} #{e.message}",
    )
  end
end
