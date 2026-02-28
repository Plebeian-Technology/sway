require "rails_helper"

RSpec.describe "OrganizationsController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  def get_params(sway_locale)
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
          icon_url: "https://www.example.com",
        },
        {
          label: Faker::String.random(length: 5),
          support: "AGAINST",
          summary: Faker::String.random(length: 20),
          icon_url: "https://www.sway.vote",
        },
      ],
    }
  end

  describe "GET /index" do
    it "gets all organizations for a sway_locale" do
      sway_locale, _user = setup
      organization = create(:organization, sway_locale:)

      get "/organizations"

      expect(JSON.parse(response.body)).to eql([organization.to_sway_json])
    end
  end

  describe "POST /organizations" do
    it "creates new Organizations for a bill" do
      sway_locale, _user = setup
      count_organizations = Organization.count
      organization_params = get_params(sway_locale)

      post organizations_path, params: organization_params

      expect(response).to have_http_status(302)
      expect(Organization.count).to eql(count_organizations + 2)

      organization_params[:organizations].each do |param|
        org = Organization.find_by(name: param[:label])

        expect(org).to_not be_nil
        expect(org.icon_url).to eql(param[:icon_url])

        org.positions.each do |position|
          expect(position.support).to eql(param[:support])
          expect(position.summary).to eql(param[:summary])
        end
      end
    end
  end
end
