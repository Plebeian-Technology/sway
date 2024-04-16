require "test_helper"

class BillsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @bill = bills(:one)
  end

  test "should get index" do
    get bills_url
    assert_response :success
  end

  test "should get new" do
    get new_bill_url
    assert_response :success
  end

  test "should create bill" do
    assert_difference("Bill.count") do
      post bills_url, params: { bill: { category: @bill.category, chamber: @bill.chamber, external_id: @bill.external_id, external_version: @bill.external_version, house_vote_date_time_utc: @bill.house_vote_date_time_utc, introduced_date_time_utc: @bill.introduced_date_time_utc, level: @bill.level, link: @bill.link, senate_vote_date_time_utc: @bill.senate_vote_date_time_utc, sponsor_id: @bill.sponsor_id, title: @bill.title } }
    end

    assert_redirected_to bill_url(Bill.last)
  end

  test "should show bill" do
    get bill_url(@bill)
    assert_response :success
  end

  test "should get edit" do
    get edit_bill_url(@bill)
    assert_response :success
  end

  test "should update bill" do
    patch bill_url(@bill), params: { bill: { category: @bill.category, chamber: @bill.chamber, external_id: @bill.external_id, external_version: @bill.external_version, house_vote_date_time_utc: @bill.house_vote_date_time_utc, introduced_date_time_utc: @bill.introduced_date_time_utc, level: @bill.level, link: @bill.link, senate_vote_date_time_utc: @bill.senate_vote_date_time_utc, sponsor_id: @bill.sponsor_id, title: @bill.title } }
    assert_redirected_to bill_url(@bill)
  end

  test "should destroy bill" do
    assert_difference("Bill.count", -1) do
      delete bill_url(@bill)
    end

    assert_redirected_to bills_url
  end
end
