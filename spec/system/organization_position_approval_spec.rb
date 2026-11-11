# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Organization position approval journey", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let!(:bill) { create(:bill, sway_locale: sway_locale, legislator: legislator, title: "Clean Water Act") }
  let(:organization) { create(:organization, sway_locale: sway_locale, name: "Environmental League") }

  let(:member_user) { create(:user, :registered, phone: "4105550001") }
  let(:admin_user) { create(:user, :registered, phone: "4105550002") }

  let!(:member_membership) do
    create(
      :user_organization_membership,
      user: member_user,
      organization: organization,
      role: :standard,
      status: :active
    )
  end
  let!(:admin_membership) do
    create(
      :user_organization_membership,
      user: admin_user,
      organization: organization,
      role: :admin,
      status: :active
    )
  end

  before do
    create(:user_legislator, user: member_user, legislator: legislator)
    create(:user_legislator, user: admin_user, legislator: legislator)
  end

  it "member proposes an organization position and admin approves it in the browser" do
    # 1. Member proposes a position
    sign_in_as(member_user)
    visit new_organization_position_path(organization)
    wait_until_loaded

    expect(page).to have_text("Add New Position", wait: 10)

    # Select bill
    find_by_id("position-bill").click
    find("[role='option']", text: bill.external_id, wait: 5).click

    # Fill in summary
    fill_in "position-summary", with: "We strongly support clean water."

    # Submit
    click_button("Save Position")

    # Member redirected to pending changes tab
    within("#app") do
      expect(page).to have_text("We strongly support clean water.", wait: 10)
      expect(page).to have_button("Pending Approval", disabled: true)
    end

    position = OrganizationBillPosition.find_by!(organization: organization, bill: bill)
    expect(position.active).to be false
    change = position.position_changes.last!
    expect(change.status).to eq("pending")
    expect(change.new_summary).to eq("We strongly support clean water.")

    # 2. Admin approves the proposal
    sign_in_as(admin_user)
    visit organization_membership_path(organization_id: organization.id, id: admin_membership.id, tab: "changes")
    wait_until_loaded

    within("#app") do
      expect(page).to have_text("We strongly support clean water.", wait: 10)
      expect(page).to have_button("Approve Change", disabled: false)
      click_button("Approve Change")
    end

    # 3. Verify active position in database and on Positions tab
    expect(page).to have_text("Change approved and position updated.", wait: 10)

    position.reload
    expect(position.active).to be true
    expect(position.summary).to eq("We strongly support clean water.")
    expect(change.reload.approved_by).to eq(admin_user)

    within("#app") do
      find("[role='tab']", text: "Positions").click
      expect(page).to have_text("We strongly support clean water.", wait: 10)
      expect(page).to have_text("Clean Water Act")
    end
  end
end
