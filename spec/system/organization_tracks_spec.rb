# frozen_string_literal: true

require "rails_helper"

# @lat: [[organization-follows-controller#Organization follows controller#Browser examples wait for the server response]]
RSpec.describe "Organization follows", type: :system, js: true do
  let(:sway_locale) do
    SwayLocale.find_by(city: "baltimore", state: "MD", country: "United States") ||
      create(:sway_locale, city: "baltimore", state: "MD", country: "United States")
  end

  it "follows an org from the list: Follow → first-follow picker → save → Tracking + count increments" do
    user = create(:user)
    complete_registration_with_active_link(user)
    organization = create(:organization, sway_locale: sway_locale, name: "Followable Org")

    sign_in_as(user)
    visit public_organizations_path
    wait_until_loaded

    card = find("[data-testid='public-organization-card']", text: "Followable Org", wait: 10)
    expect(card).to have_text("0 followers")

    card.find("[data-testid='follow-btn-#{organization.id}']").click

    # The preferences picker opens only AFTER the redirect and reload hand back
    # the real follow id. Save the defaults it starts with.
    expect(page).to have_text("Notification preferences", wait: 10)
    click_button "Save preferences"

    # What you can see: the Tracking button appears, the follower count goes
    # up, and the row is in the database.
    expect(page).to have_css("[data-testid='following-btn-#{organization.id}']", wait: 10)
    within("[data-testid='public-organization-card']", text: "Followable Org") do
      expect(page).to have_css("[data-testid='org-card-follower-count-#{organization.id}']", text: "1 follower")
    end
    follow = OrganizationTrack.find_by(user_id: user.id, organization_id: organization.id)
    expect(follow).to be_present
  end

  it "renders Tracking from server truth for an existing follow (persistence across sessions)" do
    user = create(:user)
    complete_registration_with_active_link(user)
    organization = create(:organization, sway_locale: sway_locale, name: "Already Followed Org")
    create(:organization_track, user: user, organization: organization)

    sign_in_as(user)
    visit public_organizations_path
    wait_until_loaded

    expect(page).to have_css("[data-testid='following-btn-#{organization.id}']", wait: 10)
    within("[data-testid='public-organization-card']", text: "Already Followed Org") do
      expect(page).to have_css("[data-testid='org-card-follower-count-#{organization.id}']", text: "1 follower")
    end
  end

  it "unfollows from the detail page: Tracking → Follow + count decrements + row destroyed" do
    user = create(:user)
    complete_registration_with_active_link(user)
    organization = create(:organization, sway_locale: sway_locale, name: "Unfollowable Org")
    create(:organization_track, user: user, organization: organization)

    sign_in_as(user)
    visit public_organization_path(organization)
    wait_until_loaded

    detail = find("[data-testid='public-organization-detail']", wait: 10)
    # @lat: [[testing-the-toolchain#An assertion that cannot fail proves nothing]]
    expect(detail.find("[data-testid='org-detail-follower-count']")).to have_text("1 follower")

    detail.find("[data-testid='following-btn-#{organization.id}']").click

    # The redirect and reload flip the button back to Follow and the count to
    # zero.
    expect(page).to have_css("[data-testid='follow-btn-#{organization.id}']", wait: 10)
    expect(page).to have_css("[data-testid='org-detail-follower-count']", text: "0 followers")
    expect(OrganizationTrack.find_by(user_id: user.id, organization_id: organization.id)).to be_nil
  end

  it "renders no follow control for a guest while the pages stay browseable" do
    organization = create(:organization, sway_locale: sway_locale, name: "Guest Visible Org")

    visit public_organizations_path
    expect(find_by_id("app", wait: 10)).to have_text("Guest Visible Org")
    expect(page).to have_no_css("[data-testid='follow-btn-#{organization.id}']")

    visit public_organization_path(organization)
    detail = find("[data-testid='public-organization-detail']", wait: 10)
    expect(detail).to have_text("Guest Visible Org")
    expect(page).to have_no_css("[data-testid='follow-btn-#{organization.id}']")
    expect(page).to have_no_css("[data-testid='following-btn-#{organization.id}']")
  end

  it "round-trips the org-notification master toggle on the Notifications Organizations tab" do
    user = create(:user)
    complete_registration_with_active_link(user)

    sign_in_as(user)
    visit "/notifications?tab=organizations"
    wait_until_loaded

    panel = find("[data-testid='notification-orgs-toggle']", wait: 10)
    expect(panel).to have_text("Disabled")

    # The toggle renders as an element with role="switch", and its label points
    # at it with htmlFor.
    panel.find_by_id("org-position-master", wait: 10).click
    panel.find("[data-testid='org-notifications-save']").click

    # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
    expect(page).to have_text("Organization notification defaults updated.", wait: 10)
    preference = NotificationPreference.find_by(user_id: user.id, key: "org_position_taken")
    expect(preference&.enabled).to be(true)

    # @lat: [[notifications-tab-url#The Notifications tab in the URL]]
    expect(page).to have_css("[data-testid='org-notifications-saved-state']", text: "Enabled", wait: 10)
    expect(page).to have_current_path("/notifications?tab=organizations")

    # What the server stored survives a fresh visit. The ?tab= parameter in the
    # URL is what keeps the Organizations panel open.
    visit "/notifications?tab=organizations"
    wait_until_loaded
    # @lat: [[capybara-wait-semantics#Why waiting for an absence can pass instantly]]
    expect(page).to have_css("[data-testid='org-notifications-saved-state']", text: "Enabled", wait: 10)
  end

  it "cascades a default event-type OFF to every existing follow (R6, asymmetric)" do
    user = create(:user)
    complete_registration_with_active_link(user)
    org_a = create(:organization, sway_locale: sway_locale, name: "Cascade Org A")
    org_b = create(:organization, sway_locale: sway_locale, name: "Cascade Org B")
    follow_a = create(:organization_track, user: user, organization: org_a)
    follow_b = create(:organization_track, user: user, organization: org_b)

    sign_in_as(user)
    visit "/notifications?tab=organizations"
    wait_until_loaded

    panel = find("[data-testid='notification-orgs-toggle']", wait: 10)
    # Turning the main switch on reveals a checkbox per kind of event.
    panel.find_by_id("org-position-master", wait: 10).click
    panel.find_by_id("org-notify-new-position", wait: 10).click
    panel.find("[data-testid='org-notifications-save']").click

    # @lat: [[capybara-wait-semantics#Waiting on the side effect instead]]
    expect(page).to have_text("Organization notification defaults updated.", wait: 10)
    # Switching a default OFF switches it off on every follow. The default that
    # was not touched stays on. This only works one way: switching a default
    # back ON never re-enables the individual follows.
    expect(follow_a.reload.notify_on_new_position).to be(false)
    expect(follow_b.reload.notify_on_new_position).to be(false)
    expect(follow_a.notify_on_support_change).to be(true)
    expect(follow_b.notify_on_support_change).to be(true)
  end

  it "edits an existing follow's preferences through the picker (R7)" do
    user = create(:user)
    complete_registration_with_active_link(user)
    organization = create(:organization, sway_locale: sway_locale, name: "Tunable Org")
    follow = create(:organization_track, user: user, organization: organization)

    sign_in_as(user)
    visit public_organization_path(organization)
    wait_until_loaded

    find("[data-testid='preferences-btn-#{organization.id}']", wait: 10).click
    expect(page).to have_text("Notification preferences", wait: 10)

    find_by_id("pref-new-position", wait: 10).click
    click_button "Save preferences"

    # The redirect and reload close the modal, and the follow row keeps the
    # change. `following-btn` is already on the page before this save (the
    # user already follows), so it gates nothing here — the real gate is the
    # modal closing, which is the Inertia patch's onSuccess.
    expect(page).to have_no_text("Notification preferences")
    expect(follow.reload.notify_on_new_position).to be(false)
    expect(follow.notify_on_support_change).to be(true)
  end

  # @lat: [[org-notification-cascade-and-defaults#Why the skipped-picker test separates user defaults from column defaults]]
  it "keeps the seeded defaults when the first-follow picker is skipped (R7)" do
    user = create(:user)
    user.update!(
      notify_on_new_position_default: false, org_position_cadence_default: :daily
    )
    complete_registration_with_active_link(user)
    organization = create(:organization, sway_locale: sway_locale, name: "Skipped Org")

    sign_in_as(user)
    visit public_organizations_path
    wait_until_loaded

    card = find("[data-testid='public-organization-card']", text: "Skipped Org", wait: 10)
    card.find("[data-testid='follow-btn-#{organization.id}']").click

    expect(page).to have_text("Notification preferences", wait: 10)
    click_button "Skip for now"

    # The picker's own close (`onClick={onClose}`) is client-side and races
    # nothing server-side worth gating on — the follow row was already
    # written by the earlier follow-btn POST, before the picker opened.
    expect(page).to have_no_text("Notification preferences")
    follow = OrganizationTrack.find_by(user_id: user.id, organization_id: organization.id)
    expect(follow).to be_present
    expect(follow.notify_on_new_position).to be(false)
    expect(follow.notification_cadence).to eq("daily")
  end

  it "shows the muted member badge with Preferences and no Unfollow" do
    user = create(:user)
    complete_registration_with_active_link(user)
    organization = create(:organization, sway_locale: sway_locale, name: "Member Org")
    create(:user_organization_membership, user: user, organization: organization, status: "active")
    create(:organization_track, :muted, user: user, organization: organization)

    sign_in_as(user)
    visit public_organization_path(organization)
    wait_until_loaded

    badge = find("[data-testid='member-badge-#{organization.id}']", wait: 10)
    expect(badge).to have_text("Muted · member")
    expect(page).to have_css("[data-testid='member-preferences-btn-#{organization.id}']")
    # Members never see an Unfollow button.
    expect(page).to have_no_css("[data-testid='following-btn-#{organization.id}']")
  end
end
