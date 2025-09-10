require "rails_helper"

RSpec.describe "BillsController", type: :request, inertia: true do
    include_context "SessionDouble"
    include_context "Setup"

    def get_params(sway_locale, partial_bill: {}, partial_sponsor: {}, partial_vote: {})
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
                introduced_date_time_utc: (bill.introduced_date_time_utc - 1.day)&.to_s,
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
            },
        ]
    end

    describe "GET /index", inertia: true do
        it "gets all bills for a sway locale" do
            sway_locale, _user = setup
            bill, _params = get_params(sway_locale)
            bill.save!

            get "/bills"

            expect(inertia).to render_component Pages::BILLS
            expect(inertia).to include_props(
                { bills: [bill.to_sway_json.merge({ user_vote: nil, bill_score: BillScore.new(bill:).to_sway_json })] },
            )
        end
    end

    describe "GET /show", inertia: true do
        it "gets a bill when passed an id" do
            sway_locale, _user = setup
            bill, _params = get_params(sway_locale)
            bill.save!

            get "/bills/#{bill.id}"

            expect(inertia).to render_component Pages::BILL
            expect(inertia).to include_props(
                { bill: bill.to_sway_json, organizations: [], legislator_votes: [], user_vote: nil },
            )
        end
    end

    describe "GET /new", inertia: true do
        it "renders the bill creator with a new bill" do
            sway_locale, _user = setup
            bill, _params = get_params(sway_locale)
            bill.save!

            get "/bills/new"

            expect(inertia).to render_component Pages::BILL_CREATOR
            expect(inertia).to include_props(
                {
                    bill: Bill.new.attributes,
                    legislators: sway_locale.legislators.map(&:to_sway_json),
                    organizations: [],
                    legislator_votes: [],
                    tab_key: nil,
                },
            )
        end
    end

    describe "GET /edit", inertia: true do
        it "renders the bill creator with a bill from params" do
            sway_locale, _user = setup
            bill, _params = get_params(sway_locale)
            bill.save!

            get "/bills/#{bill.id}/edit"

            expect(inertia).to render_component Pages::BILL_CREATOR
            expect(inertia).to include_props(
                {
                    bills: [bill.to_sway_json],
                    bill: bill.to_sway_json.tap { |b| b[:organizations] = [] },
                    legislators: sway_locale.legislators.map(&:to_sway_json),
                    organizations: [],
                    legislator_votes: [],
                    tab_key: nil,
                },
            )
        end
    end

    describe "POST /create", inertia: true do
        it "creates a new bill" do
            sway_locale, _user = setup

            count_bills = Bill.count
            count_votes = Vote.count

            bill, params = get_params(sway_locale)

            post "/bills", params: params

            expect(response).to have_http_status(200)

            expect(Bill.count).to eql(count_bills + 1)
            expect(Bill.last.external_id).to eql(bill.external_id)
            expect(Vote.count).to eql(count_votes + 1)
            expect(Vote.last.senate_roll_call_vote_number).to eql(2)
        end

        def spec_create_failure(key)
            sway_locale, _user = setup
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

    describe "PUT /update", inertia: true do
        it "updates a bill" do
            sway_locale, _user = setup
            bill, _params = get_params(sway_locale)
            bill.save!

            put "/bills/#{bill.id}", params: { summary: "Tacos are super great!" }

            body = JSON.parse(response.body)
            expect(body.fetch("route")).to include(edit_bill_path(bill.id))

            get body.fetch("route")

            expect(inertia).to render_component Pages::BILL_CREATOR
            expect(inertia.props[:bill].deep_symbolize_keys).to eql(
                bill.to_sway_json.deep_symbolize_keys.tap do |b|
                    b[:summary] = "Tacos are super great!"
                    b[:organizations] = []
                end,
            )
        end
    end
end
