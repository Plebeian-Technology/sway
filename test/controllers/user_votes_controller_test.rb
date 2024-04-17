require "test_helper"

class UserVotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_vote = user_votes(:one)
  end

  test "should get index" do
    get user_votes_url
    assert_response :success
  end

  test "should get new" do
    get new_user_vote_url
    assert_response :success
  end

  test "should create user_vote" do
    assert_difference("UserVote.count") do
      post user_votes_url, params: { user_vote: { bill_id: @user_vote.bill_id, support: @user_vote.support, user_id: @user_vote.user_id } }
    end

    assert_redirected_to user_vote_url(UserVote.last)
  end

  test "should show user_vote" do
    get user_vote_url(@user_vote)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_vote_url(@user_vote)
    assert_response :success
  end

  test "should update user_vote" do
    patch user_vote_url(@user_vote), params: { user_vote: { bill_id: @user_vote.bill_id, support: @user_vote.support, user_id: @user_vote.user_id } }
    assert_redirected_to user_vote_url(@user_vote)
  end

  test "should destroy user_vote" do
    assert_difference("UserVote.count", -1) do
      delete user_vote_url(@user_vote)
    end

    assert_redirected_to user_votes_url
  end
end
