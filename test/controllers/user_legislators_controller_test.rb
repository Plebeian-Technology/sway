require "test_helper"

class UserLegislatorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_legislator = user_legislators(:one)
  end

  test "should get index" do
    get user_legislators_url
    assert_response :success
  end

  test "should get new" do
    get new_user_legislator_url
    assert_response :success
  end

  test "should create user_legislator" do
    assert_difference("UserLegislator.count") do
      post user_legislators_url, params: { user_legislator: { legislator_id: @user_legislator.legislator_id, user_id: @user_legislator.user_id } }
    end

    assert_redirected_to user_legislator_url(UserLegislator.last)
  end

  test "should show user_legislator" do
    get user_legislator_url(@user_legislator)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_legislator_url(@user_legislator)
    assert_response :success
  end

  test "should update user_legislator" do
    patch user_legislator_url(@user_legislator), params: { user_legislator: { legislator_id: @user_legislator.legislator_id, user_id: @user_legislator.user_id } }
    assert_redirected_to user_legislator_url(@user_legislator)
  end

  test "should destroy user_legislator" do
    assert_difference("UserLegislator.count", -1) do
      delete user_legislator_url(@user_legislator)
    end

    assert_redirected_to user_legislators_url
  end
end
