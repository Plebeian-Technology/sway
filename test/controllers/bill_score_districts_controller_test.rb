# typed: true
require "test_helper"

class BillScoreDistrictsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bill_score_district = bill_score_districts(:one)
  end

  test "should get index" do
    get bill_score_districts_url
    assert_response :success
  end

  test "should get new" do
    get new_bill_score_district_url
    assert_response :success
  end

  test "should create bill_score_district" do
    assert_difference("BillScoreDistrict.count") do
      post bill_score_districts_url, params: { bill_score_district: { against: @bill_score_district.against, bill_score_id: @bill_score_district.bill_score_id, district: @bill_score_district.district, for: @bill_score_district.for } }
    end

    assert_redirected_to bill_score_district_url(BillScoreDistrict.last)
  end

  test "should show bill_score_district" do
    get bill_score_district_url(@bill_score_district)
    assert_response :success
  end

  test "should get edit" do
    get edit_bill_score_district_url(@bill_score_district)
    assert_response :success
  end

  test "should update bill_score_district" do
    patch bill_score_district_url(@bill_score_district), params: { bill_score_district: { against: @bill_score_district.against, bill_score_id: @bill_score_district.bill_score_id, district: @bill_score_district.district, for: @bill_score_district.for } }
    assert_redirected_to bill_score_district_url(@bill_score_district)
  end

  test "should destroy bill_score_district" do
    assert_difference("BillScoreDistrict.count", -1) do
      delete bill_score_district_url(@bill_score_district)
    end

    assert_redirected_to bill_score_districts_url
  end
end
