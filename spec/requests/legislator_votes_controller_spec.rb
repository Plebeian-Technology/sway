require "rails_helper"

RSpec.describe "LegislatorVotesController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:build_legislator_vote_params) do
    lambda do |sway_locale|
      legislator = create(:legislator)
      bill =
        create(
          :bill,
          sway_locale:,
          summary:
            "Summary from spec - spec/requests/legislator_votes_controller_spec.rb",
        )

      {
        bill_id: bill.id,
        legislator_votes: [{ support: "FOR", legislator_id: legislator.id }],
      }
    end
  end

  describe "POST /legislator_votes" do
    it "creates new Legislator Votes for a bill" do
      sway_locale, _user = setup

      count_legislator_votes = LegislatorVote.count

      params = build_legislator_vote_params.call(sway_locale)
      post legislator_votes_path, params: params

      expect(response).to have_http_status(302)

      expect(LegislatorVote.count).to eql(count_legislator_votes + 1)
      latest_vote = LegislatorVote.last!
      expect(latest_vote.bill_id).to eql(params[:bill_id])
      expect(latest_vote.legislator_id).to eql(
        params[:legislator_votes].first[:legislator_id],
      )
      expect(latest_vote.support).to eql("FOR")
    end

    # def spec_create_failure(key)
    #   sway_locale, _user = setup
    #   count_bills = Bill.count

    #   partial_bill = {}
    #   partial_bill[key] = nil
    #   _bill, params = get_params(sway_locale, partial_bill:)

    #   post "/bills", params: params

    #   expect(response).to have_http_status(302)
    #   expect(Bill.count).to eql(count_bills)
    #   follow_redirect!
    #   expect(inertia.props[:errors][key]).to eql(["can't be blank"])
    # end

    # it "does not create a new bill, because the external_id is missing" do
    #   spec_create_failure(:external_id)
    # end
  end
end
