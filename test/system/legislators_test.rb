require "application_system_test_case"

class LegislatorsTest < ApplicationSystemTestCase
  setup do
    @legislator = legislators(:one)
  end

  test "visiting the index" do
    visit legislators_url
    assert_selector "h1", text: "Legislators"
  end

  test "should create legislator" do
    visit legislators_url
    click_on "New legislator"

    check "Active" if @legislator.active
    fill_in "Address", with: @legislator.address_id
    fill_in "District", with: @legislator.district
    fill_in "Email", with: @legislator.email
    fill_in "External", with: @legislator.external_id
    fill_in "Fax", with: @legislator.fax
    fill_in "First name", with: @legislator.first_name
    fill_in "Last name", with: @legislator.last_name
    fill_in "Link", with: @legislator.link
    fill_in "Party", with: @legislator.party
    fill_in "Phone", with: @legislator.phone
    fill_in "Photo url", with: @legislator.photo_url
    fill_in "Title", with: @legislator.title
    click_on "Create Legislator"

    assert_text "Legislator was successfully created"
    click_on "Back"
  end

  test "should update Legislator" do
    visit legislator_url(@legislator)
    click_on "Edit this legislator", match: :first

    check "Active" if @legislator.active
    fill_in "Address", with: @legislator.address_id
    fill_in "District", with: @legislator.district
    fill_in "Email", with: @legislator.email
    fill_in "External", with: @legislator.external_id
    fill_in "Fax", with: @legislator.fax
    fill_in "First name", with: @legislator.first_name
    fill_in "Last name", with: @legislator.last_name
    fill_in "Link", with: @legislator.link
    fill_in "Party", with: @legislator.party
    fill_in "Phone", with: @legislator.phone
    fill_in "Photo url", with: @legislator.photo_url
    fill_in "Title", with: @legislator.title
    click_on "Update Legislator"

    assert_text "Legislator was successfully updated"
    click_on "Back"
  end

  test "should destroy Legislator" do
    visit legislator_url(@legislator)
    click_on "Destroy this legislator", match: :first

    assert_text "Legislator was successfully destroyed"
  end
end
