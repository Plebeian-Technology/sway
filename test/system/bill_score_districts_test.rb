# typed: false
require "application_system_test_case"

class BillScoreDistrictsTest < ApplicationSystemTestCase
  setup do
    @bill_score_district = bill_score_districts(:one)
  end

  test "visiting the index" do
    visit bill_score_districts_url
    assert_selector "h1", text: "Bill score districts"
  end

  test "should create bill score district" do
    visit bill_score_districts_url
    click_on "New bill score district"

    fill_in "Against", with: @bill_score_district.against
    fill_in "Bill score", with: @bill_score_district.bill_score_id
    fill_in "District", with: @bill_score_district.district
    fill_in "For", with: @bill_score_district.for
    click_on "Create Bill score district"

    assert_text "Bill score district was successfully created"
    click_on "Back"
  end

  test "should update Bill score district" do
    visit bill_score_district_url(@bill_score_district)
    click_on "Edit this bill score district", match: :first

    fill_in "Against", with: @bill_score_district.against
    fill_in "Bill score", with: @bill_score_district.bill_score_id
    fill_in "District", with: @bill_score_district.district
    fill_in "For", with: @bill_score_district.for
    click_on "Update Bill score district"

    assert_text "Bill score district was successfully updated"
    click_on "Back"
  end

  test "should destroy Bill score district" do
    visit bill_score_district_url(@bill_score_district)
    click_on "Destroy this bill score district", match: :first

    assert_text "Bill score district was successfully destroyed"
  end
end
