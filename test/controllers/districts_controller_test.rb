require "test_helper"

class DistrictsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @district = districts(:one)
  end

  test "should get index" do
    get districts_url
    assert_response :success
  end

  test "should get new" do
    get new_district_url
    assert_response :success
  end

  test "should create district" do
    assert_difference("District.count") do
      post districts_url, params: { district: { name: @district.name } }
    end

    assert_redirected_to district_url(District.last)
  end

  test "should show district" do
    get district_url(@district)
    assert_response :success
  end

  test "should get edit" do
    get edit_district_url(@district)
    assert_response :success
  end

  test "should update district" do
    patch district_url(@district), params: { district: { name: @district.name } }
    assert_redirected_to district_url(@district)
  end

  test "should destroy district" do
    assert_difference("District.count", -1) do
      delete district_url(@district)
    end

    assert_redirected_to districts_url
  end
end
