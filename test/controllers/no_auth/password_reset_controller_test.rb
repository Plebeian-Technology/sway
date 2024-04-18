require "test_helper"

class NoAuth::PasswordResetControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get no_auth_password_reset_index_url
    assert_response :success
  end
end
