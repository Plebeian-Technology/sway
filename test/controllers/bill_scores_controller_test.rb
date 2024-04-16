require "test_helper"

class BillScoresControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bill_score = bill_scores(:one)
  end

  test "should get index" do
    get bill_scores_url
    assert_response :success
  end

  test "should get new" do
    get new_bill_score_url
    assert_response :success
  end

  test "should create bill_score" do
    assert_difference("BillScore.count") do
      post bill_scores_url, params: { bill_score: { bill_id: @bill_score.bill_id } }
    end

    assert_redirected_to bill_score_url(BillScore.last)
  end

  test "should show bill_score" do
    get bill_score_url(@bill_score)
    assert_response :success
  end

  test "should get edit" do
    get edit_bill_score_url(@bill_score)
    assert_response :success
  end

  test "should update bill_score" do
    patch bill_score_url(@bill_score), params: { bill_score: { bill_id: @bill_score.bill_id } }
    assert_redirected_to bill_score_url(@bill_score)
  end

  test "should destroy bill_score" do
    assert_difference("BillScore.count", -1) do
      delete bill_score_url(@bill_score)
    end

    assert_redirected_to bill_scores_url
  end
end
