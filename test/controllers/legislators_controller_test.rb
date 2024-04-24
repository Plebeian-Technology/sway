# typed: true
require "test_helper"

class LegislatorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @legislator = legislators(:one)
  end

  test "should get index" do
    get legislators_url
    assert_response :success
  end

  test "should get new" do
    get new_legislator_url
    assert_response :success
  end

  test "should create legislator" do
    assert_difference("Legislator.count") do
      post legislators_url, params: { legislator: { active: @legislator.active, address_id: @legislator.address_id, district: @legislator.district, email: @legislator.email, external_id: @legislator.external_id, fax: @legislator.fax, first_name: @legislator.first_name, last_name: @legislator.last_name, link: @legislator.link, party: @legislator.party, phone: @legislator.phone, photo_url: @legislator.photo_url, title: @legislator.title } }
    end

    assert_redirected_to legislator_url(Legislator.last)
  end

  test "should show legislator" do
    get legislator_url(@legislator)
    assert_response :success
  end

  test "should get edit" do
    get edit_legislator_url(@legislator)
    assert_response :success
  end

  test "should update legislator" do
    patch legislator_url(@legislator), params: { legislator: { active: @legislator.active, address_id: @legislator.address_id, district: @legislator.district, email: @legislator.email, external_id: @legislator.external_id, fax: @legislator.fax, first_name: @legislator.first_name, last_name: @legislator.last_name, link: @legislator.link, party: @legislator.party, phone: @legislator.phone, photo_url: @legislator.photo_url, title: @legislator.title } }
    assert_redirected_to legislator_url(@legislator)
  end

  test "should destroy legislator" do
    assert_difference("Legislator.count", -1) do
      delete legislator_url(@legislator)
    end

    assert_redirected_to legislators_url
  end
end
