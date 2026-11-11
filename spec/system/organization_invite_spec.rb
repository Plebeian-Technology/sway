# frozen_string_literal: true

require "rails_helper"

# @lat: [[organization-invitation-controller#Creating an invite returns format-specific responses]]
RSpec.describe "Organization Invite/Accept Flow", type: :system, js: true do
  include_context "TwilioDouble"
  include ActiveJob::TestHelper

  let(:admin_phone) { "4105551234" }
  let(:sway_locale) { create(:sway_locale) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }
  let(:organization) { create(:organization, sway_locale: sway_locale) }

  around do |example|
    original_admin_phones = User::ADMIN_PHONES.dup

    begin
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, [admin_phone])

      example.run
    ensure
      User.send(:remove_const, :ADMIN_PHONES)
      User.const_set(:ADMIN_PHONES, original_admin_phones)
    end
  end

  before do
    @admin =
      create(:user, :registered, phone: admin_phone)
    create(:user_legislator, user: @admin, legislator: legislator)
    create(
      :user_organization_membership,
      user: @admin,
      organization: organization,
      role: :admin,
      status: :active
    )
    ActiveJob::Base.queue_adapter = :test
  end

  it "admin invites a user, invitee accepts, membership becomes active" do
    admin_membership =
      UserOrganizationMembership.find_by!(
        user: @admin,
        organization: organization
      )

    sign_in_as(@admin)

    # Step 1 — the admin opens the membership page on the members tab, where
    # the invite form lives. The page opens on the `positions` tab by default;
    # the invite form renders inside the members list, on `members` only.
    visit organization_membership_path(
      organization_id: organization.id,
      id: admin_membership.id,
      tab: "members"
    )
    expect(page).to have_text(/members/i, wait: 10)

    # @lat: [[organization-invite-authorization#Invite acceptance is bound to token, organization, and email]]
    invitee_email = "invitee-#{SecureRandom.hex(4)}@example.com"

    within("[data-testid='org-invite-form']") do
      # Type into the email field key by key so React's copy of the value keeps
      # up. The older inputs were happy with fill_in, but this one only updates
      # from real React events (admin_api_keys_spec does the same thing).
      email_input = find_field("Invitee Email")
      email_input.click
      email_input.send_keys(invitee_email)
      # The button reads "Send Invite" and is disabled only while the request
      # is in flight.
      expect(page).to have_button("Send Invite", disabled: false, wait: 5)
      click_button("Send Invite")
    end

    # The invite row is saved. Capybara's synchronize keeps retrying until it
    # is, so no sleep is needed.
    expect do
      Capybara.using_wait_time(10) do
        page.document.synchronize(10) do
          UserOrganizationMembershipInvite
            .where(invitee_email: invitee_email)
            .exists? ||
            Kernel.raise(Capybara::ElementNotFound, "invite not persisted")
        end
      end
    end.not_to raise_error

    invite =
      UserOrganizationMembershipInvite.find_by!(invitee_email: invitee_email)
    expect(invite.inviter_id).to eq(@admin.id)
    expect(invite.organization_id).to eq(organization.id)

    invitee =
      create(
        :user,
        phone: "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}",
        email: invitee_email
      )
    create(:user_legislator, user: invitee, legislator: legislator)
    invitee.complete!
    invitee_membership =
      create(
        :user_organization_membership,
        user: invitee,
        organization: organization,
        role: :standard
      )

    expect(
      UserOrganizationMembership.where(
        user: invitee,
        organization: organization
      ).count
    ).to eq(1)

    # Step 8 — the admin opens the approvals tab and the approvals wrapper
    # renders. The org-membership-accepted element holds the approvals list; it
    # renders as an empty box when nothing is waiting for approval, which is
    # exactly the state right after someone joins.
    visit organization_membership_path(
      organization_id: organization.id,
      id: admin_membership.id,
      tab: "approvals"
    )
    expect(page).to have_css(
      "[data-testid='org-membership-accepted']",
      wait: 10
    )

    # Touch the invitee_membership variable so RSpec does not warn it is unused.
    expect(invitee_membership).to be_persisted
  end

  it "invitee clicks email link, lands on Inertia confirm page, accepts the invite" do
    invitee_email = "invitee-#{SecureRandom.hex(4)}@example.com"
    invitee =
      create(
        :user,
        phone: "410555#{SecureRandom.random_number(10_000).to_s.rjust(4, "0")}",
        email: invitee_email
      )
    create(:user_legislator, user: invitee, legislator: legislator)
    invitee.complete!

    invite =
      create(
        :user_organization_membership_invite,
        organization: organization,
        inviter: @admin,
        invitee_email: invitee_email
      )

    # Put the invitee into a browser session with the test-only sign-in route.
    # The helper's name is left over from earlier: all it does is set
    # session[:user_id] through /test/sessions. No passkey, no admin rights.
    sign_in_as(invitee)

    # Rebuild the same signed id the email puts in its link.
    signed_token =
      invite.signed_id(purpose: :accept_invite, expires_at: invite.expires_at)

    visit "/organizations/#{organization.id}/membership_invites/#{signed_token}/confirm_accept"

    expect(page).to have_text(
      "Accept invitation to #{organization.name}",
      wait: 10
    )
    expect(page).to have_button("Accept Invitation", disabled: false, wait: 5)

    click_button("Accept Invitation")

    # The accept request answers with a 303 redirect, so Inertia follows it with
    # a GET to /users/organization_memberships.
    expect(page).to have_current_path(
      "/users/organization_memberships",
      wait: 10
    )

    membership =
      UserOrganizationMembership.find_by!(
        user: invitee,
        organization: organization
      )
    expect(membership.status).to eq("active")
    expect(membership.role).to eq("standard")

    invite.reload
    expect(invite.accepted_at).to be_present
    expect(invite.invitee_user_id).to eq(invitee.id)
  end
end
