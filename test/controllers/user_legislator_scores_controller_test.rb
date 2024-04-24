# typed: true
require "test_helper"

class UserLegislatorScoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_legislator_score = user_legislator_scores(:one)
  end

  test "should get index" do
    get user_legislator_scores_url
    assert_response :success
  end

  test "should get new" do
    get new_user_legislator_score_url
    assert_response :success
  end

  test "should create user_legislator_score" do
    assert_difference("UserLegislatorScore.count") do
      post user_legislator_scores_url, params: { user_legislator_score: { count_agreed: @user_legislator_score.count_agreed, count_disagreed: @user_legislator_score.count_disagreed, count_legislator_abstained: @user_legislator_score.count_legislator_abstained, count_no_legislator_vote: @user_legislator_score.count_no_legislator_vote, user_legislator_id: @user_legislator_score.user_legislator_id } }
    end

    assert_redirected_to user_legislator_score_url(UserLegislatorScore.last)
  end

  test "should show user_legislator_score" do
    get user_legislator_score_url(@user_legislator_score)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_legislator_score_url(@user_legislator_score)
    assert_response :success
  end

  test "should update user_legislator_score" do
    patch user_legislator_score_url(@user_legislator_score), params: { user_legislator_score: { count_agreed: @user_legislator_score.count_agreed, count_disagreed: @user_legislator_score.count_disagreed, count_legislator_abstained: @user_legislator_score.count_legislator_abstained, count_no_legislator_vote: @user_legislator_score.count_no_legislator_vote, user_legislator_id: @user_legislator_score.user_legislator_id } }
    assert_redirected_to user_legislator_score_url(@user_legislator_score)
  end

  test "should destroy user_legislator_score" do
    assert_difference("UserLegislatorScore.count", -1) do
      delete user_legislator_score_url(@user_legislator_score)
    end

    assert_redirected_to user_legislator_scores_url
  end
end
