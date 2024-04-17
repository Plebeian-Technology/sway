require "test_helper"

class UserInvitesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user_invite = user_invites(:one)
  end

  test "should get index" do
    get user_invites_url
    assert_response :success
  end

  test "should get new" do
    get new_user_invite_url
    assert_response :success
  end

  test "should create user_invite" do
    assert_difference("UserInvite.count") do
      post user_invites_url, params: { user_invite: { invite_accepted_on_utc: @user_invite.invite_accepted_on_utc, invite_expires_on_utc: @user_invite.invite_expires_on_utc, invitee_email: @user_invite.invitee_email, user_id: @user_invite.user_id } }
    end

    assert_redirected_to user_invite_url(UserInvite.last)
  end

  test "should show user_invite" do
    get user_invite_url(@user_invite)
    assert_response :success
  end

  test "should get edit" do
    get edit_user_invite_url(@user_invite)
    assert_response :success
  end

  test "should update user_invite" do
    patch user_invite_url(@user_invite), params: { user_invite: { invite_accepted_on_utc: @user_invite.invite_accepted_on_utc, invite_expires_on_utc: @user_invite.invite_expires_on_utc, invitee_email: @user_invite.invitee_email, user_id: @user_invite.user_id } }
    assert_redirected_to user_invite_url(@user_invite)
  end

  test "should destroy user_invite" do
    assert_difference("UserInvite.count", -1) do
      delete user_invite_url(@user_invite)
    end

    assert_redirected_to user_invites_url
  end
end
