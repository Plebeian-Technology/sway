# typed: true
# frozen_string_literal: true

class ScoreUpdaterService
  extend T::Sig

  sig { params(user_vote: UserVote).void }
  def initialize(user_vote)
    @user_vote = user_vote

    @user = T.let(nil, T.nilable(User))
    @bill = T.let(nil, T.nilable(Bill))
    @sway_locale = T.let(nil, T.nilable(SwayLocale))

    @districts = T.let(nil, T.nilable(T::Array[District]))
    @bill_districts = T.let(nil, T.nilable(T::Array[District]))
    @user_districts = T.let(nil, T.nilable(T::Array[District]))

    Rails.logger.info(
      "ScoreUpdaterService.new - initialized service with UserVote - #{user_vote.id}",
    )
  end

  def run
    update_bill_score_districts(update_bill_score)
    update_legislator_district_score
    update_user_legislator_scores
  end

  private

  sig { returns(BillScore) }
  def update_bill_score
    BillScore.find_or_create_by(bill:).update_score(@user_vote)
  end

  sig { params(bill_score: BillScore).returns(T::Array[BillScoreDistrict]) }
  def update_bill_score_districts(bill_score)
    districts.map do |district|
      BillScoreDistrict.find_or_create_by!(district:, bill_score:).update_score(
        @user_vote,
      )
    end
  end

  sig { returns(T::Array[LegislatorDistrictScore]) }
  def update_legislator_district_score
    user
      .legislators(sway_locale)
      .map do |l|
        LegislatorDistrictScore.find_or_create_by!(legislator: l).update_score(
          @user_vote,
        )
      end
  end

  sig { returns(T::Array[UserLegislatorScore]) }
  def update_user_legislator_scores
    user
      .user_legislators_by_locale(sway_locale)
      .map do |ul|
        UserLegislatorScore.find_or_create_by!(
          user_legislator: ul,
        ).update_score(@user_vote)
      end
  end

  sig { returns(T::Array[District]) }
  def districts
    T.cast(
      @districts ||= bill_districts.select { |d| user_districts.include?(d) },
      T::Array[District],
    )
  end

  sig { returns(T::Array[District]) }
  def bill_districts
    @bill_districts ||= sway_locale.districts.to_a
  end

  sig { returns(T::Array[District]) }
  def user_districts
    T.cast(@user_districts ||= user.districts(sway_locale), T::Array[District])
  end

  sig { returns(User) }
  def user
    @user ||= @user_vote.user
  end

  sig { returns(Bill) }
  def bill
    @bill ||= @user_vote.bill
  end

  sig { returns(SwayLocale) }
  def sway_locale
    @sway_locale ||= bill.sway_locale
  end
end
