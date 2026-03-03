require "rails_helper"

RSpec.describe "BillsController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:build_bill_params) do
    lambda do |sway_locale, partial_bill: {}, partial_sponsor: {}, partial_vote: {}|
      legislator = create(:legislator)
      bill = build(:bill, legislator:, sway_locale:, summary: "Tacos are great")

      [
        bill,
        {
          external_id: bill.external_id,
          external_version: bill.external_version,
          title: bill.title,
          link: bill.link,
          chamber: bill.chamber,
          introduced_date_time_utc:
            (bill.introduced_date_time_utc - 1.day)&.to_s,
          house_vote_date_time_utc: bill.house_vote_date_time_utc&.to_s,
          senate_vote_date_time_utc: bill.senate_vote_date_time_utc&.to_s,
          category: bill.category,
          summary: bill.summary,
          status: bill.status,
          active: true,
          audio_bucket_path: bill.audio_bucket_path,
          audio_by_line: bill.audio_by_line,
          sway_locale_id: sway_locale.id,
          legislator_id: legislator.id,
          house_roll_call_vote_number: 1,
          senate_roll_call_vote_number: 2,
          **partial_bill, # must be at end
          **partial_sponsor,
          **partial_vote,
        },
      ]
    end
  end

  describe "GET /index" do
    it "gets all bills for a sway locale" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/bills"

      expect(inertia).to render_component Pages::BILLS
      expect(inertia).to have_props(
        {
          bills: [
            bill.to_sway_json.merge(
              { user_vote: nil, bill_score: bill.bill_score.to_sway_json },
            ),
          ],
        },
      )
    end
  end

  describe "GET /show" do
    it "gets a bill when passed an id" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/bills/#{bill.id}"

      expect(inertia).to render_component Pages::BILL
      empty_values = []
      # @type var empty_values: Array[untyped]
      expect(inertia).to have_props(
        {
          bill: bill.to_sway_json,
          organizations: empty_values,
          legislator_votes: empty_values,
          user_vote: nil,
        },
      )
    end
  end

  describe "GET /new" do
    it "renders the bill creator with a new bill" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/bills/new"

      expect(inertia).to render_component Pages::BILL_CREATOR
      empty_values = []
      # @type var empty_values: Array[untyped]
      expect(inertia).to have_props(
        {
          bill: Bill.new.attributes,
          legislators: sway_locale.legislators.map(&:to_sway_json),
          organizations: empty_values,
          legislator_votes: empty_values,
          tab_key: nil,
        },
      )
    end
  end

  describe "GET /edit" do
    it "renders the bill creator with a bill from params" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      get "/bills/#{bill.id}/edit"

      expect(inertia).to render_component Pages::BILL_CREATOR
      empty_values = []
      # @type var empty_values: Array[untyped]
      expect(inertia).to have_props(
        {
          bills: [bill.to_sway_json],
          bill: bill.to_sway_json.tap { |b| b[:organizations] = empty_values },
          legislators: sway_locale.legislators.map(&:to_sway_json),
          organizations: empty_values,
          legislator_votes: empty_values,
          tab_key: nil,
        },
      )
    end
  end

  describe "POST /create" do
    let(:spec_create_failure) do
      lambda do |key|
        sway_locale, _user = setup
        count_bills = Bill.count

        partial_bill = {}
        # @type var partial_bill: Hash[Symbol, untyped]
        partial_bill[key] = nil
        _bill, params = build_bill_params.call(sway_locale, partial_bill:)

        post "/bills", params: params

        expect(response).to have_http_status(302)
        expect(Bill.count).to eql(count_bills)
        follow_redirect!
        expect(inertia.props[:errors][key].first).to include("can't be blank")
      end
    end

    it "creates a new bill" do
      sway_locale, _user = setup

      count_bills = Bill.count
      count_votes = Vote.count

      bill, params = build_bill_params.call(sway_locale)

      post "/bills", params: params

      expect(response).to have_http_status(200)

      expect(Bill.count).to eql(count_bills + 1)
      expect(Bill.last!.external_id).to eql(bill.external_id)
      expect(Vote.count).to eql(count_votes + 1)
      expect(Vote.last!.senate_roll_call_vote_number).to eql(2)
    end

    it "does not create a new bill, because the external_id is missing" do
      spec_create_failure.call(:external_id)
    end

    it "does not create a new bill, because the category is missing" do
      spec_create_failure.call(:category)
    end

    it "does not create a new bill, because the chamber is missing" do
      spec_create_failure.call(:chamber)
    end

    it "does not create a new bill, because the introduced_date_time_utc is missing" do
      spec_create_failure.call(:introduced_date_time_utc)
    end

    it "does not create a new bill, because the link is missing" do
      spec_create_failure.call(:link)
    end

    it "does not create a new bill, because the status is missing" do
      spec_create_failure.call(:status)
    end

    it "does not create a new bill, because the summary is missing" do
      spec_create_failure.call(:summary)
    end

    it "does not create a new bill, because the title is missing" do
      spec_create_failure.call(:title)
    end

    it "does not create a new bill, because the sway_locale_id is missing" do
      spec_create_failure.call(:sway_locale_id)
    end
  end

  describe "PUT /update" do
    it "updates a bill" do
      sway_locale, _user = setup
      bill, _params = build_bill_params.call(sway_locale)
      bill.save!

      put "/bills/#{bill.id}", params: { summary: "Tacos are super great!" }

      body = JSON.parse(response.body)
      expect(body.fetch("route")).to include(edit_bill_path(bill.id))

      get body.fetch("route")

      expect(inertia).to render_component Pages::BILL_CREATOR
      empty_values = []
      # @type var empty_values: Array[untyped]
      expect(inertia.props[:bill].deep_symbolize_keys).to eql(
        bill.to_sway_json.deep_symbolize_keys.tap do |b|
          b[:summary] = "Tacos are super great!"
          b[:organizations] = empty_values
        end,
      )
    end
  end
end
