# frozen_string_literal: true

require "rails_helper"

# @lat: [[admin-hub-and-tabs#Why /admin exists]]
RSpec.describe "Admin hub", type: :system, js: true do
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:sway_admin_user) { create(:user, :sway_admin) }

  before { create(:user_legislator, user: sway_admin_user, legislator: legislator) }

  it "lists the operator tools and navigates to Pipeline Run History" do
    run = create(:legislation_pipeline_run, :completed)

    sign_in_as(sway_admin_user)
    visit "/admin"
    wait_until_loaded

    expect(page).to have_text(
      "Tools for managing Sway content, settings, and operator state.", wait: 10
    )
    expect(page).to have_text("Bill Creator")
    expect(page).to have_text("LLM Settings")
    expect(page).to have_text("Categories")

    click_link "Pipeline Run History"

    expect(page).to have_css("[data-testid='pipeline-runs-index']", wait: 10)
    expect(page).to have_css("[data-testid='pipeline-run-row-#{run.id}']", wait: 10)
    expect(page).to have_text("completed")
  end

  it "renders the runs empty state when no pipeline runs exist" do
    sign_in_as(sway_admin_user)
    visit "/pipeline_runs"
    wait_until_loaded

    index = find("[data-testid='pipeline-runs-index']", wait: 10)
    expect(index).to have_text("No pipeline runs yet.")
  end
end
