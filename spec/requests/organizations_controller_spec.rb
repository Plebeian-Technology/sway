require "rails_helper"

RSpec.describe "OrganizationsController admin gate", type: :request do
  empty_array = [] #: Array[untyped]

  include_examples "requires sway admin",
    verb: :post,
    path: "/organizations",
    params: {organizations: empty_array}

  # @lat: [[organization-position-removal#Renaming an organization changes it everywhere in its locale]]
  include_examples "requires sway admin",
    verb: :patch,
    path: "/organizations/1",
    params: {name: "Renamed"}
end

RSpec.describe "OrganizationsController", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  def get_params(sway_locale)
    bill =
      create(
        :bill,
        sway_locale:,
        summary:
          "Summary from spec - spec/requests/legislator_votes_controller_spec.rb"
      )

    {
      bill_id: bill.id,
      organizations: [
        {
          label: Faker::Alphanumeric.alphanumeric(number: 5),
          support: "FOR",
          summary: Faker::String.random(length: 20),
          icon_url: "https://www.example.com"
        },
        {
          label: Faker::Alphanumeric.alphanumeric(number: 5),
          support: "AGAINST",
          summary: Faker::String.random(length: 20),
          icon_url: "https://www.sway.vote"
        }
      ]
    }
  end

  describe "POST /organizations" do
    it "creates new Organizations for a bill" do
      sway_locale, = setup
      count_organizations = Organization.count
      organization_params = get_params(sway_locale)

      post organizations_path, params: organization_params

      expect(response).to have_http_status(302)
      expect(Organization.count).to eql(count_organizations + 2)

      organization_params[:organizations].each do |param|
        org = Organization.find_by!(name: param[:label])
        expect(org.icon_url).to eql(param[:icon_url])

        org.positions.each do |position|
          expect(position.support).to eql(param[:support])
          expect(position.summary).to eql(param[:summary])
        end
      end
    end

    # @lat: [[organization-position-removal#A saved position is a published one]]
    it "publishes what it saved, so the bill actually lists the organization" do
      sway_locale, = setup
      organization_params = get_params(sway_locale)
      bill = Bill.find(organization_params[:bill_id])

      post organizations_path, params: organization_params

      labels = organization_params[:organizations].pluck(:label)
      expect(bill.reload.organizations.pluck(:name)).to match_array(labels)
      expect(OrganizationBillPosition.where(bill_id: bill.id).pluck(:active)).to all(be(true))
    end

    # @lat: [[organizations-controller#Icon addresses keep their source meaning]]
    describe "the icon_url column" do
      it "stays empty when an admin uploads an icon" do
        sway_locale, = setup
        blob = ActiveStorage::Blob.create_and_upload!(
          io: StringIO.new("icon"),
          filename: "icon.png",
          content_type: "image/png"
        )
        params = get_params(sway_locale)
        params[:organizations][0] = params[:organizations][0].merge(
          icon_url: nil,
          icon_signed_id: blob.signed_id
        )

        post organizations_path, params: params

        org = Organization.find_by!(name: params[:organizations][0][:label])
        expect(org.icon).to be_attached
        expect(org.icon_url).to be_nil
      end

      it "refuses an address of ours that the form handed back" do
        sway_locale, = setup
        params = get_params(sway_locale)
        params[:organizations][0] = params[:organizations][0].merge(
          icon_url: "https://localhost:3333/rails/active_storage/blobs/proxy/abc/icon.png"
        )

        post organizations_path, params: params

        org = Organization.find_by!(name: params[:organizations][0][:label])
        expect(org.icon_url).to be_nil
      end
    end

    # @lat: [[bill-creator-shell#The Bill Creator shell#Why tab URLs retain legacy compatibility]]
    it "redirects to the Summary tab when submitted from Summary" do
      sway_locale, = setup
      organization_params = get_params(sway_locale).merge(tab_key: "summary")
      bill_id = organization_params[:bill_id]

      post organizations_path, params: organization_params

      expect(response).to have_http_status(302)
      expect(response.location).to include("/admin/bill_creator/#{bill_id}/summary")
      expect(response.location).not_to include("tab_key=")
    end

    it "redirects to the Creator tab when submitted from Creator" do
      sway_locale, = setup
      organization_params = get_params(sway_locale).merge(tab_key: "creator")
      bill_id = organization_params[:bill_id]

      post organizations_path, params: organization_params

      expect(response).to have_http_status(302)
      expect(response.location).to include("/admin/bill_creator/#{bill_id}/creator")
    end

    it "falls back to the Positions tab when tab_key is unknown" do
      sway_locale, = setup
      organization_params = get_params(sway_locale).merge(tab_key: "garbage")
      bill_id = organization_params[:bill_id]

      post organizations_path, params: organization_params

      expect(response).to have_http_status(302)
      expect(response).to redirect_to(
        positions_bill_creator_path(
          id: bill_id,
          saved: "Supporting/Opposing Arguments Saved",
          event_key: "organizations"
        )
      )
    end

    # @lat: [[toasts#Toasts#Flash toast dedupe]]
    it "surfaces a success flash notice on the followed redirect" do
      sway_locale, = setup
      organization_params = get_params(sway_locale)

      post organizations_path, params: organization_params
      follow_redirect!

      expect(inertia).to have_flash(notice: "Supporting/Opposing Arguments Saved")
    end

    # @lat: [[organizations-controller#Create errors retain their row and field shape]]
    it "populates the field-error payload when a position fails validation" do
      sway_locale, = setup
      params = get_params(sway_locale)
      params[:organizations][0][:summary] = "" # blank summary → position invalid

      post organizations_path, params: params
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      org_errors = inertia.props[:errors][:organizations]
      expect(org_errors[0][:summary]).to be_present
    end

    it "rolls back the first org/position when a later one fails (transactional)" do
      sway_locale, = setup
      params = get_params(sway_locale)
      first_label = params[:organizations][0][:label]
      params[:organizations][1][:summary] = "" # second position invalid

      expect {
        post organizations_path, params: params
      }.not_to change(Organization, :count)

      expect(Organization.find_by(name: first_label)).to be_nil
    end

    # @lat: [[organization-position-removal#A Neutral position carries no testimony]]
    it "saves a Neutral (ABSTAIN) position with a blank summary by substituting DEFAULT_SUMMARY" do
      sway_locale, = setup
      bill = create(:bill, sway_locale:, summary: "Summary from spec")
      org = create(:organization, sway_locale:, name: "Neutral Coalition")

      post organizations_path, params: {
        bill_id: bill.id,
        organizations: [
          {
            value: org.id,
            label: org.name,
            support: "ABSTAIN",
            summary: "",
            icon_url: nil
          }
        ]
      }

      expect(response).to have_http_status(302)
      position = OrganizationBillPosition.find_by!(organization_id: org.id, bill_id: bill.id)
      expect(position.support).to eq("ABSTAIN")
      expect(position.summary).to eq(OrganizationBillPosition::DEFAULT_SUMMARY)
      expect(position.active).to be(true)
    end

    # @lat: [[organizations-controller#Organization lookup stays within the bill's locale]]
    it "matches an existing organization in the bill's locale case-insensitively and ignores cross-locale organization ids" do
      sway_locale, = setup
      other_locale = create(:sway_locale, :congress)
      bill = create(:bill, sway_locale:, summary: "Summary from spec")
      existing_local = create(:organization, sway_locale:, name: "Harford Road Neighbors")
      foreign_org = create(:organization, sway_locale: other_locale, name: "Foreign Group")

      expect {
        post organizations_path, params: {
          bill_id: bill.id,
          organizations: [
            {
              value: -1,
              label: "  harford   road neighbors ",
              support: "FOR",
              summary: "Supports the bill.",
              icon_url: nil
            },
            {
              value: foreign_org.id,
              label: "Local Replacement",
              support: "AGAINST",
              summary: "Opposes the bill.",
              icon_url: nil
            }
          ]
        }
      }.to change { Organization.where(sway_locale: sway_locale).count }.by(1)

      expect(OrganizationBillPosition.find_by(organization_id: existing_local.id, bill_id: bill.id)).to be_present
      expect(OrganizationBillPosition.find_by(organization_id: foreign_org.id, bill_id: bill.id)).to be_nil
    end
  end

  describe "organization membership redirects" do
    it "canonicalizes an organization tab from an active member's URL" do
      _, admin = setup
      organization = create(:organization)
      admin_membership = create(:user_organization_membership, user: admin, organization:, role: :admin)
      member = create(:user)
      membership = create(:user_organization_membership, user: member, organization:)

      delete organization_membership_path(organization, membership),
        params: {org_tab: "members", tab: "changes"}

      expect(response).to have_http_status(:redirect)
      uri = URI.parse(response.location)
      expect(uri.path).to eq(organization_membership_path(organization, admin_membership))
      redirect_query = URI.decode_www_form(uri.query.to_s).to_h
      expect(redirect_query["org_tab"]).to eq("members")
      expect(redirect_query).not_to have_key("tab")
    end

    it "reads the legacy tab_key when redirecting back to the membership page" do
      _, admin = setup
      organization = create(:organization)
      create(:user_organization_membership, user: admin, organization:, role: :admin)
      member = create(:user)
      membership = create(:user_organization_membership, user: member, organization:)

      delete organization_membership_path(organization, membership), params: {tab_key: "members"}

      expect(response).to have_http_status(:redirect)
      uri = URI.parse(response.location)
      redirect_query = URI.decode_www_form(uri.query.to_s).to_h
      expect(redirect_query["org_tab"]).to eq("members")
      expect(redirect_query).not_to have_key("tab_key")
    end
  end

  # @lat: [[surfaces#Dual-rendered JSON]]
  describe "GET /organizations/:id" do
    it "renders the organization as JSON with its bill positions and no members" do
      sway_locale, = setup
      organization = create(:organization, sway_locale:)
      bill = create(:bill, sway_locale:)
      create(
        :organization_bill_position,
        organization:,
        bill:,
        support: "FOR"
      )

      get "/organizations/#{organization.id}"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["id"]).to eq(organization.id)
      expect(body["name"]).to eq(organization.name)
      expect(body).to have_key("positions")
      expect(body["positions"].length).to eq(1)
      expect(body).not_to have_key("members")
      expect(body).not_to have_key("memberships")
    end

    it "returns a 404 not_found envelope for an unknown id" do
      setup

      get "/organizations/0"

      # This used to answer 200 with { success: false }; it is now a real 404 error envelope.
      expect(response).to have_http_status(:not_found)
      expect(response.parsed_body.dig("error", "code")).to eq("not_found")
      expect(response.parsed_body.dig("error", "message")).to eq("Organization not found.")
    end
  end

  # @lat: [[organization-position-removal#Renaming an organization changes it everywhere in its locale]]
  describe "PATCH /organizations/:id" do
    it "renames the organization and PRG-redirects back to the tab it was submitted from" do
      sway_locale, = setup
      org = create(:organization, sway_locale:, name: "Md Tenants Union")
      bill = create(:bill, sway_locale:)

      patch "/organizations/#{org.id}",
        params: {name: "Maryland Tenants Union", bill_id: bill.id, tab_key: "summary"}

      expect(response).to have_http_status(302)
      expect(response.location).to include("/admin/bill_creator/#{bill.id}/summary")
      expect(org.reload.name).to eq("Maryland Tenants Union")
    end

    it "surfaces a success flash notice on the followed redirect" do
      sway_locale, = setup
      org = create(:organization, sway_locale:, name: "Old Name")
      bill = create(:bill, sway_locale:)

      patch "/organizations/#{org.id}", params: {name: "New Name", bill_id: bill.id, tab_key: "summary"}
      follow_redirect!

      expect(inertia).to have_flash(notice: "Organization renamed to New Name.")
    end

    it "does not rename when the new name collides with another org in the locale" do
      sway_locale, = setup
      create(:organization, sway_locale:, name: "Existing Org")
      org = create(:organization, sway_locale:, name: "Org To Rename")
      bill = create(:bill, sway_locale:)

      patch "/organizations/#{org.id}", params: {name: "Existing Org", bill_id: bill.id, tab_key: "summary"}

      expect(response).to have_http_status(302)
      expect(org.reload.name).to eq("Org To Rename")
    end

    it "ignores mass-assignment of sway_locale_id (name-only permit list)" do
      sway_locale, = setup
      other_locale = create(:sway_locale)
      org = create(:organization, sway_locale:, name: "Scoped Org")
      bill = create(:bill, sway_locale:)

      patch "/organizations/#{org.id}",
        params: {name: "Scoped Org Renamed", sway_locale_id: other_locale.id, bill_id: bill.id, tab_key: "summary"}

      expect(org.reload.sway_locale_id).to eq(sway_locale.id)
    end
  end
end
