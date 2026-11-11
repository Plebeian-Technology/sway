# frozen_string_literal: true

require "rails_helper"

# @lat: [[production-snapshot-deploy-rehearsal-harness#What spec/system/production_snapshot_spec.rb checks in a real browser]]
RSpec.describe "Production snapshot browser flows", :production_snapshot, type: :system, js: true do
  include_context "production snapshot (migrated)"

  after do
    Array(@active_authenticators).reverse_each do |authenticator_id|
      disable_virtual_authenticator(authenticator_id)
    end
  end

  it "issues a passkey challenge for an existing production user's stored credentials" do
    user = User.joins(:passkeys).order(:id).first ||
      raise("production snapshot has no passkey users")

    visit root_path
    expect(page).to have_field("Phone number")

    response = browser_json_request(
      "POST", "/users/webauthn/sessions", {phone: user.phone}
    )

    expect(response["status"]).to eq(200)
    expect(response.dig("body", "flow")).to eq("passkey")
    offered_credential_ids =
      (response.dig("body", "options", "allowCredentials") || []).pluck("id")
    expect(offered_credential_ids).to match_array(user.passkeys.map(&:external_id))
  end

  it "keeps an existing production user on the passkey path (no SMS re-verification, no new account)" do
    user = User.joins(:passkeys).order(:id).first ||
      raise("production snapshot has no passkey users")
    users_before = User.count

    visit root_path
    # A fake authenticator that does NOT hold this user's credential makes the
    # browser's credential lookup fail straight away, the same way every time.
    @active_authenticators = [enable_virtual_authenticator]

    fill_in "Phone number", with: user.phone
    click_button "Continue with Phone"

    # The sign-in fails in the browser because the credential is not on this
    # machine, but the user must never be sent into the SMS or registration flow.
    expect(page).to have_button("Continue with Phone", wait: 10)
    expect(page).to have_no_field("v2-code")
    expect(User.count).to eq(users_before)
  end

  it "renders public organizations with real production data" do
    organization = Organization.order(:id).first

    visit public_organizations_path

    expect(page).to have_text(organization.name, wait: 10)
  end
end
