require "test_helper"

class LegislatorVotesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @legislator_vote = legislator_votes(:one)
  end

  test "should get index" do
    get legislator_votes_url
    assert_response :success
  end

  test "should get new" do
    get new_legislator_vote_url
    assert_response :success
  end

  test "should create legislator_vote" do
    assert_difference("LegislatorVote.count") do
      post legislator_votes_url, params: { legislator_vote: { bill_id: @legislator_vote.bill_id, legislator_id: @legislator_vote.legislator_id, support: @legislator_vote.support } }
    end

    assert_redirected_to legislator_vote_url(LegislatorVote.last)
  end

  test "should show legislator_vote" do
    get legislator_vote_url(@legislator_vote)
    assert_response :success
  end

  test "should get edit" do
    get edit_legislator_vote_url(@legislator_vote)
    assert_response :success
  end

  test "should update legislator_vote" do
    patch legislator_vote_url(@legislator_vote), params: { legislator_vote: { bill_id: @legislator_vote.bill_id, legislator_id: @legislator_vote.legislator_id, support: @legislator_vote.support } }
    assert_redirected_to legislator_vote_url(@legislator_vote)
  end

  test "should destroy legislator_vote" do
    assert_difference("LegislatorVote.count", -1) do
      delete legislator_vote_url(@legislator_vote)
    end

    assert_redirected_to legislator_votes_url
  end
end
