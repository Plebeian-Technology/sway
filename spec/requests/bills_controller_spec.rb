require "rails_helper"

RSpec.describe "BillsController", type: :request, inertia: true do
  include_context "SessionDouble"

  def setup
    address = create(:address)
    sway_locale = create(:sway_locale, city: address.city, state: address.region_code, country: address.country)
    district = create(:district, sway_locale:)
    legislator = create(:legislator, address:, district:)

    user = create(:user, is_registration_complete: true) do |u|
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, u.phone)
      session_hash[:user_id] = u.id
    end

    create(:user_legislator, user:, legislator:)

    sway_locale
  end

  def get_params(sway_locale, partial_bill: {}, partial_sponsor: {}, partial_vote: {})
    legislator = create(:legislator)
    bill = build(:bill, summary: "Tacos are great")

    [bill, {
      external_id: bill.external_id,
      external_version: bill.external_version,
      title: bill.title,
      link: bill.link,
      chamber: bill.chamber,
      introduced_date_time_utc: bill.introduced_date_time_utc,
      house_vote_date_time_utc: bill.house_vote_date_time_utc,
      senate_vote_date_time_utc: bill.senate_vote_date_time_utc,
      category: bill.category,
      level: bill.level,
      summary: bill.summary,
      status: bill.status,
      active: true,
      audio_bucket_path: bill.audio_bucket_path,
      audio_by_line: bill.audio_by_line,
      sway_locale_id: sway_locale.id,
      legislator_id: legislator.id,
      house_roll_call_vote_number: 1,
      senate_roll_call_vote_number: 2,
      **partial_bill # must be at end
    }]
  end

  describe "POST /create", inertia: true do
    it "creates a new bill" do
      sway_locale = setup

      count_bills = Bill.count
      count_votes = Vote.count

      bill, params = get_params(sway_locale)

      post "/bills", params: params

      expect(response).to have_http_status(302)
      expect(Bill.count).to eql(count_bills + 1)
      expect(Bill.last.external_id).to eql(bill.external_id)
      expect(Vote.count).to eql(count_votes + 1)
      expect(Vote.last.senate_roll_call_vote_number).to eql(2)
    end

    def spec_create_failure(key)
      sway_locale = setup
      count_bills = Bill.count

      partial_bill = {}
      partial_bill[key] = nil
      _bill, params = get_params(sway_locale, partial_bill:)

      post "/bills", params: params

      expect(response).to have_http_status(302)
      expect(Bill.count).to eql(count_bills)
      follow_redirect!
      expect(inertia.props[:errors][key].first).to include("can't be blank")
    end

    it "does not create a new bill, because the external_id is missing" do
      spec_create_failure(:external_id)
    end

    it "does not create a new bill, because the category is missing" do
      spec_create_failure(:category)
    end

    it "does not create a new bill, because the chamber is missing" do
      spec_create_failure(:chamber)
    end

    it "does not create a new bill, because the introduced_date_time_utc is missing" do
      spec_create_failure(:introduced_date_time_utc)
    end

    # Level is set automatically
    # it "does not create a new bill, because the level is missing" do
    #   spec_create_failure(:level)
    # end

    it "does not create a new bill, because the link is missing" do
      spec_create_failure(:link)
    end

    it "does not create a new bill, because the status is missing" do
      spec_create_failure(:status)
    end

    it "does not create a new bill, because the summary is missing" do
      spec_create_failure(:summary)
    end

    it "does not create a new bill, because the title is missing" do
      spec_create_failure(:title)
    end

    it "does not create a new bill, because the sway_locale_id is missing" do
      spec_create_failure(:sway_locale_id)
    end
  end
end
