# typed: false
require "application_system_test_case"

class BillsTest < ApplicationSystemTestCase
  setup do
    @bill = bills(:one)
  end

  test "visiting the index" do
    visit bills_url
    assert_selector "h1", text: "Bills"
  end

  test "should create bill" do
    visit bills_url
    click_on "New bill"

    fill_in "Category", with: @bill.category
    fill_in "Chamber", with: @bill.chamber
    fill_in "External", with: @bill.external_id
    fill_in "External version", with: @bill.external_version
    fill_in "House vote date time utc", with: @bill.house_vote_date_time_utc
    fill_in "Introduced date time utc", with: @bill.introduced_date_time_utc
    fill_in "Level", with: @bill.level
    fill_in "Link", with: @bill.link
    fill_in "Senate vote date time utc", with: @bill.senate_vote_date_time_utc
    fill_in "Sponsor", with: @bill.sponsor_id
    fill_in "Title", with: @bill.title
    click_on "Create Bill"

    assert_text "Bill was successfully created"
    click_on "Back"
  end

  test "should update Bill" do
    visit bill_url(@bill)
    click_on "Edit this bill", match: :first

    fill_in "Category", with: @bill.category
    fill_in "Chamber", with: @bill.chamber
    fill_in "External", with: @bill.external_id
    fill_in "External version", with: @bill.external_version
    fill_in "House vote date time utc", with: @bill.house_vote_date_time_utc
    fill_in "Introduced date time utc", with: @bill.introduced_date_time_utc
    fill_in "Level", with: @bill.level
    fill_in "Link", with: @bill.link
    fill_in "Senate vote date time utc", with: @bill.senate_vote_date_time_utc
    fill_in "Sponsor", with: @bill.sponsor_id
    fill_in "Title", with: @bill.title
    click_on "Update Bill"

    assert_text "Bill was successfully updated"
    click_on "Back"
  end

  test "should destroy Bill" do
    visit bill_url(@bill)
    click_on "Destroy this bill", match: :first

    assert_text "Bill was successfully destroyed"
  end
end
