# frozen_string_literal: true

require "rails_helper"

# @lat: [[production-snapshot-deploy-rehearsal-harness#What production_data_compatibility_spec.rb checks]]
RSpec.describe "Production snapshot data compatibility", :production_snapshot, type: :request do
  include_context "production snapshot (migrated)"

  it "answers sign-in initiation with a passkey challenge for every production user" do
    users = User.includes(:passkeys).order(:id).to_a
    expect(users).not_to be_empty

    users.each do |user|
      expect(user.has_sway_passkey?).to be(true), "user #{user.id} lost passkey visibility"

      post "/users/webauthn/sessions", params: {phone: user.phone}, as: :json

      expect(response).to have_http_status(:ok), "user #{user.id}: #{response.status}"
      body = response.parsed_body
      expect(body["flow"]).to eq("passkey"), "user #{user.id} was routed to the #{body["flow"].inspect} flow"

      offered_credential_ids =
        (body.dig("options", "allowCredentials") || []).pluck("id")
      expect(offered_credential_ids).to match_array(user.passkeys.map(&:external_id)),
        "user #{user.id}: challenge does not offer their stored credentials"
    end
  end

  it "serves the signed-out home page" do
    get "/"

    expect(response).to have_http_status(:ok)
  end

  it "serves the public organizations pages with real data" do
    get public_organizations_path
    expect(response).to have_http_status(:ok)

    organization = Organization.order(:id).first
    get public_organization_path(organization)
    expect(response).to have_http_status(:ok)
  end

  it "renders bills index, every bill page, and legislators for a completed production user" do
    user = User.where(is_registration_complete: true).order(:id).first
    expect(user).to be_present
    sign_in(user)

    get "/bills"
    expect(response).to have_http_status(:ok)

    Bill.order(:id).find_each do |bill|
      get "/bills/#{bill.id}"
      expect(response).to have_http_status(:ok),
        "GET /bills/#{bill.id} (#{bill.external_id}) -> #{response.status}"
    end

    get "/legislators"
    expect(response).to have_http_status(:ok)

    get "/legislators", params: {legislators_tab: "history"}
    expect(response).to have_http_status(:ok)

    linked_legislator = user&.user_legislators&.first&.legislator || Legislator.order(:id).first
    expect(linked_legislator).to be_present
    get "/legislators/#{linked_legislator&.id}"
    expect(response).to have_http_status(:ok)

    if (bill_1290_sponsor = Bill.find_by(id: 1290)&.legislator)
      get "/legislators/#{bill_1290_sponsor.id}"
      expect(response).to have_http_status(:ok)
    end

    linked_ids = UserLegislator.where(user_id: user&.id).select(:legislator_id)
    unlinked_sponsor = Bill.where.not(legislator_id: linked_ids).order(:id).first&.legislator
    expect(unlinked_sponsor).to be_present
    get "/legislators/#{unlinked_sponsor&.id}"
    expect(response).to have_http_status(:ok)
  end
end
