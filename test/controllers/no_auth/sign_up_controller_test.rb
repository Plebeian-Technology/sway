# typed: false
require "test_helper"

class NoAuth::SignUpControllerTest < ActionDispatch::IntegrationTest
  test "should get index" do
    get no_auth_sign_up_index_url
    assert_response :success
  end
end
