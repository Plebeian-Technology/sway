require "rails_helper"

RSpec.describe "OrganizationsController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  def get_params(
    sway_locale,
    partial_bill: {},
    partial_sponsor: {},
    partial_vote: {}
  )
    bill =
      create(
        :bill,
        sway_locale:,
        summary:
          "Summary from spec - spec/requests/legislator_votes_controller_spec.rb",
      )

    {
      bill_id: bill.id,
      organizations: [
        {
          label: Faker::String.random(length: 5),
          support: "FOR",
          summary: Faker::String.random(length: 20),
          icon_path: "https://www.example.com",
        },
        {
          label: Faker::String.random(length: 5),
          support: "AGAINST",
          summary: Faker::String.random(length: 20),
          icon_path: "https://www.sway.vote",
        },
      ],
    }
  end

  describe "POST /organizations", inertia: true do
    it "creates new Organizations for a bill" do
      sway_locale, = setup
      count_organizations = Organization.count
      organization_params = get_params(sway_locale)

      post organizations_path, params: organization_params

      expect(response).to have_http_status(302)
      expect(Organization.count).to eql(count_organizations + 2)

      organization_params[:organizations].each do |param|
        org = Organization.find_by(name: param[:label])

        expect(org).to_not be_nil
        expect(org.icon_path).to eql(param[:icon_path])

        org.positions.each do |position|
          expect(position.support).to eql(param[:support])
          expect(position.summary).to eql(param[:summary])
        end
      end
    end

    # def spec_create_failure(key)
    #   sway_locale = setup
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
