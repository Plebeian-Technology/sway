require "test_helper"

class UsersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
  end

  test "should get index" do
    get users_url
    assert_response :success
  end

  test "should get new" do
    get new_user_url
    assert_response :success
  end

  test "should create user" do
    assert_difference("User.count") do
      post users_url, params: { user: { address_id: @user.address_id, email: @user.email, is_admin: @user.is_admin, is_email_verified: @user.is_email_verified, is_registered_to_vote: @user.is_registered_to_vote, is_registration_complete: @user.is_registration_complete, last_login_utc: @user.last_login_utc, phone: @user.phone } }
    end

    assert_redirected_to user_url(User.last)
  end

  test "should show user" do
    get user_url(@user)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_url(@user)
    assert_response :success
  end

  test "should update user" do
    patch user_url(@user), params: { user: { address_id: @user.address_id, email: @user.email, is_admin: @user.is_admin, is_email_verified: @user.is_email_verified, is_registered_to_vote: @user.is_registered_to_vote, is_registration_complete: @user.is_registration_complete, last_login_utc: @user.last_login_utc, phone: @user.phone } }
    assert_redirected_to user_url(@user)
  end

  test "should destroy user" do
    assert_difference("User.count", -1) do
      delete user_url(@user)
    end

    assert_redirected_to users_url
  end
end
