# typed: true
require "test_helper"

class UserDistrictsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_district = user_districts(:one)
  end

  test "should get index" do
    get user_districts_url
    assert_response :success
  end

  test "should get new" do
    get new_user_district_url
    assert_response :success
  end

  test "should create user_district" do
    assert_difference("UserDistrict.count") do
      post user_districts_url, params: { user_district: { district_id: @user_district.district_id, user_id: @user_district.user_id } }
    end

    assert_redirected_to user_district_url(UserDistrict.last)
  end

  test "should show user_district" do
    get user_district_url(@user_district)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_district_url(@user_district)
    assert_response :success
  end

  test "should update user_district" do
    patch user_district_url(@user_district), params: { user_district: { district_id: @user_district.district_id, user_id: @user_district.user_id } }
    assert_redirected_to user_district_url(@user_district)
  end

  test "should destroy user_district" do
    assert_difference("UserDistrict.count", -1) do
      delete user_district_url(@user_district)
    end

    assert_redirected_to user_districts_url
  end
end
