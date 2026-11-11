# frozen_string_literal: true

require "rails_helper"

# The endpoint behind Surface 6's two
# buttons — "Confirm as a sending service" and "Remove this label" / "Not a
# sending service".

RSpec.describe "SendingServiceDomains admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :patch,
    path: "/sending_service_domains/1",
    params: {label: "confirmed", bill_id: 1}
end

RSpec.describe "PATCH /sending_service_domains/:id", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:admin) { create(:user, :sway_admin) }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  let(:domain) { create(:sending_service_domain, domain: "everyactioncustom.com") }

  before do
    session_hash[:user_id] = admin.id
  end

  describe "a successful confirmation" do
    it "redirects to the pipeline tab and confirms the domain" do
      patch sending_service_domain_path(domain), params: {label: "confirmed", bill_id: bill.id}

      expect(response).to redirect_to(pipeline_bill_creator_path(id: bill.id))
      domain.reload
      expect(domain.label).to eq(SendingServiceDomain::CONFIRMED)
      expect(domain.confirmed_by).to eq(admin)
    end

    it "reports back a success notice, not an error" do
      patch sending_service_domain_path(domain), params: {label: "confirmed", bill_id: bill.id}
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:errors]).to be_blank
    end
  end

  describe "a successful removal" do
    before { domain.update!(label: SendingServiceDomain::CONFIRMED, confirmed_by: admin, confirmed_at: Time.current) }

    it "redirects to the pipeline tab and clears the domain's label" do
      patch sending_service_domain_path(domain), params: {label: "none", bill_id: bill.id}

      expect(response).to redirect_to(pipeline_bill_creator_path(id: bill.id))
      domain.reload
      expect(domain.label).to eq(SendingServiceDomain::NO_LABEL)
      expect(domain.confirmed_by).to be_nil
    end
  end

  describe "every refusal reaches the operator by name, under the sending_service key" do
    it "refuses with a message for an unknown label value" do
      patch sending_service_domain_path(domain), params: {label: "bogus", bill_id: bill.id}
      follow_redirect!

      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:errors][:sending_service]).to be_present
      domain.reload
      expect(domain.label).to eq(SendingServiceDomain::NO_LABEL)
    end
  end

  # WR-10. bill_id names only the screen to return to, so a request without
  # it is answerable — but the redirect helper raised UrlGenerationError on
  # every branch INCLUDING the success one, so the label was written and the
  # operator got a 500 with no way to tell whether it took effect.
  describe "a request with no bill_id" do
    it "still writes the label and answers with a redirect, not a server error" do
      patch sending_service_domain_path(domain), params: {label: "confirmed"}

      expect(response).to have_http_status(:redirect)
      expect(domain.reload.label).to eq(SendingServiceDomain::CONFIRMED)
    end

    it "refuses an unknown label the same way, without a server error" do
      patch sending_service_domain_path(domain), params: {label: "bogus"}

      expect(response).to have_http_status(:redirect)
      expect(domain.reload.label).to eq(SendingServiceDomain::NO_LABEL)
    end
  end

  describe "a request with an array-valued bill_id" do
    it "falls back to the admin hub instead of building a nonsense path" do
      patch sending_service_domain_path(domain), params: {label: "confirmed", bill_id: ["1", "2"]}

      expect(response).to redirect_to(admin_root_path)
      expect(domain.reload.label).to eq(SendingServiceDomain::CONFIRMED)
    end
  end
end
