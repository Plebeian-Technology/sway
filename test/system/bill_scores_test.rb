# typed: false
require "application_system_test_case"

class BillScoresTest < ApplicationSystemTestCase
  setup do
    @bill_score = bill_scores(:one)
  end

  test "visiting the index" do
    visit bill_scores_url
    assert_selector "h1", text: "Bill scores"
  end

  test "should create bill score" do
    visit bill_scores_url
    click_on "New bill score"

    fill_in "Bill", with: @bill_score.bill_id
    click_on "Create Bill score"

    assert_text "Bill score was successfully created"
    click_on "Back"
  end

  test "should update Bill score" do
    visit bill_score_url(@bill_score)
    click_on "Edit this bill score", match: :first

    fill_in "Bill", with: @bill_score.bill_id
    click_on "Update Bill score"

    assert_text "Bill score was successfully updated"
    click_on "Back"
  end

  test "should destroy Bill score" do
    visit bill_score_url(@bill_score)
    click_on "Destroy this bill score", match: :first

    assert_text "Bill score was successfully destroyed"
  end
end
