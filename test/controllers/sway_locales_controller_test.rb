require "test_helper"

class SwayLocalesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @sway_locale = sway_locales(:one)
  end

  test "should get index" do
    get sway_locales_url
    assert_response :success
  end

  test "should get new" do
    get new_sway_locale_url
    assert_response :success
  end

  test "should create sway_locale" do
    assert_difference("SwayLocale.count") do
      post sway_locales_url, params: { sway_locale: { city: @sway_locale.city, country: @sway_locale.country, state: @sway_locale.state } }
    end

    assert_redirected_to sway_locale_url(SwayLocale.last)
  end

  test "should show sway_locale" do
    get sway_locale_url(@sway_locale)
    assert_response :success
  end

  test "should get edit" do
    get edit_sway_locale_url(@sway_locale)
    assert_response :success
  end

  test "should update sway_locale" do
    patch sway_locale_url(@sway_locale), params: { sway_locale: { city: @sway_locale.city, country: @sway_locale.country, state: @sway_locale.state } }
    assert_redirected_to sway_locale_url(@sway_locale)
  end

  test "should destroy sway_locale" do
    assert_difference("SwayLocale.count", -1) do
      delete sway_locale_url(@sway_locale)
    end

    assert_redirected_to sway_locales_url
  end
end
