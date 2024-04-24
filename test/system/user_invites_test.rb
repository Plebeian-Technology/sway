# typed: false
require "application_system_test_case"

class UserInvitesTest < ApplicationSystemTestCase
  setup do
    @user_invite = user_invites(:one)
  end

  test "visiting the index" do
    visit user_invites_url
    assert_selector "h1", text: "User invites"
  end

  test "should create user invite" do
    visit user_invites_url
    click_on "New user invite"

    fill_in "Invite accepted on utc", with: @user_invite.invite_accepted_on_utc
    fill_in "Invite expires on utc", with: @user_invite.invite_expires_on_utc
    fill_in "Invitee email", with: @user_invite.invitee_email
    fill_in "User", with: @user_invite.user_id
    click_on "Create User invite"

    assert_text "User invite was successfully created"
    click_on "Back"
  end

  test "should update User invite" do
    visit user_invite_url(@user_invite)
    click_on "Edit this user invite", match: :first

    fill_in "Invite accepted on utc", with: @user_invite.invite_accepted_on_utc
    fill_in "Invite expires on utc", with: @user_invite.invite_expires_on_utc
    fill_in "Invitee email", with: @user_invite.invitee_email
    fill_in "User", with: @user_invite.user_id
    click_on "Update User invite"

    assert_text "User invite was successfully updated"
    click_on "Back"
  end

  test "should destroy User invite" do
    visit user_invite_url(@user_invite)
    click_on "Destroy this user invite", match: :first

    assert_text "User invite was successfully destroyed"
  end
end
