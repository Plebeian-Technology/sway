require "application_system_test_case"

class LegislatorVotesTest < ApplicationSystemTestCase
  setup do
    @legislator_vote = legislator_votes(:one)
  end

  test "visiting the index" do
    visit legislator_votes_url
    assert_selector "h1", text: "Legislator votes"
  end

  test "should create legislator vote" do
    visit legislator_votes_url
    click_on "New legislator vote"

    fill_in "Bill", with: @legislator_vote.bill_id
    fill_in "Legislator", with: @legislator_vote.legislator_id
    fill_in "Support", with: @legislator_vote.support
    click_on "Create Legislator vote"

    assert_text "Legislator vote was successfully created"
    click_on "Back"
  end

  test "should update Legislator vote" do
    visit legislator_vote_url(@legislator_vote)
    click_on "Edit this legislator vote", match: :first

    fill_in "Bill", with: @legislator_vote.bill_id
    fill_in "Legislator", with: @legislator_vote.legislator_id
    fill_in "Support", with: @legislator_vote.support
    click_on "Update Legislator vote"

    assert_text "Legislator vote was successfully updated"
    click_on "Back"
  end

  test "should destroy Legislator vote" do
    visit legislator_vote_url(@legislator_vote)
    click_on "Destroy this legislator vote", match: :first

    assert_text "Legislator vote was successfully destroyed"
  end
end
