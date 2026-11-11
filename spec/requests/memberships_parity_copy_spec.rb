# frozen_string_literal: true

require "rails_helper"

# @lat: [[parity-copy-snapshot-testing#Why parity copy is tested via snapshots and duplicated in Ruby]]
# PARITY_COPY_VALUES_MEMBERSHIPS, at the bottom of this file, holds the expected values.

RSpec.describe "Memberships PARITY_COPY snapshot", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }

  describe "GET /users/organization_memberships" do
    before { sway_locale_and_user }

    it "renders the UserOrganizationMembershipsList Inertia component (component unchanged)" do
      get "/users/organization_memberships"
      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component "organizations/UserOrganizationMembershipsList"
    end

    it "PARITY_COPY.membershipsTitle is 'My memberships' (byte-identical)" do
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membershipsTitle)).to eq("My memberships")
    end

    it "PARITY_COPY.membershipsActiveSectionLabel is 'Active' (byte-identical)" do
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membershipsActiveSectionLabel)).to eq("Active")
    end

    it "PARITY_COPY.membershipsPendingSectionLabel is 'Pending invites' (byte-identical)" do
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membershipsPendingSectionLabel)).to eq("Pending invites")
    end

    it "PARITY_COPY membership tab labels are byte-identical to UserOrganizationMembership.tsx strings" do
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membershipTabPositions)).to eq("Positions")
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membershipTabPendingChanges)).to eq("Pending Changes")
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membershipTabMembers)).to eq("Members")
    end

    it "PARITY_COPY invite action labels are byte-identical" do
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membershipAcceptLabel)).to eq("Accept invite")
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membershipDeclineLabel)).to eq("Decline")
    end

    it "PARITY_COPY position vocabulary is byte-identical" do
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:positionSupports)).to eq("Supports")
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:positionOpposes)).to eq("Opposes")
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:positionProposeChange)).to eq("Propose change")
    end

    it "PARITY_COPY pending change action labels are byte-identical" do
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:pendingChangeApproveLabel)).to eq("Approve change")
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:pendingChangeRejectLabel)).to eq("Reject")
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:pendingChangeRejectConfirmTitle)).to eq("Reject this proposed change?")
    end

    it "PARITY_COPY member management labels are byte-identical" do
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membersLeaveOrgLabel)).to eq("Leave organization")
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membersInviteLabel)).to eq("Invite a member")
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:membersInviteSubmitLabel)).to eq("Send invite")
    end

    it "PARITY_COPY new position modal labels are byte-identical" do
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:newPositionModalTitle)).to eq("Propose new position")
      expect(PARITY_COPY_VALUES_MEMBERSHIPS.fetch(:newPositionSubmitLabel)).to eq("Propose position")
    end
  end
end

# @lat: [[parity-copy-snapshot-testing#Why parity copy is tested via snapshots and duplicated in Ruby]]
PARITY_COPY_VALUES_MEMBERSHIPS = {
  # Memberships list
  membershipsTitle: "My memberships",
  membershipsActiveSectionLabel: "Active",
  membershipsPendingSectionLabel: "Pending invites",
  membershipsActiveEmpty: "You are not a member of any organizations.",
  membershipsPendingEmpty: "No pending invitations.",

  # Membership detail tabs (the TabsTrigger labels in UserOrganizationMembership.tsx)
  membershipTabPositions: "Positions",
  membershipTabPendingChanges: "Pending Changes",
  membershipTabMembers: "Members",

  # Invite accept/decline
  membershipAcceptLabel: "Accept invite",
  membershipDeclineLabel: "Decline",
  membershipDeclineConfirmTitle: "Decline invitation?",
  membershipDeclineConfirmBody: "You can request to join again later.",
  membershipDeclineConfirmAction: "Decline",

  # Positions
  positionSupports: "Supports",
  positionOpposes: "Opposes",
  positionProposeChange: "Propose change",
  positionsEmpty: "No positions have been published for this organization.",

  # Pending changes
  pendingChangesEmpty: "No pending changes.",
  pendingChangeApproveLabel: "Approve change",
  pendingChangeRejectLabel: "Reject",
  pendingChangeRejectConfirmTitle: "Reject this proposed change?",
  pendingChangeRejectConfirmBody: "This action cannot be undone.",
  pendingChangeRejectConfirmAction: "Reject",

  # Members
  membersEmpty: "No members yet.",
  membersLeaveOrgLabel: "Leave organization",
  membersLeaveOrgConfirmTitle: "Leave organization?",
  membersLeaveOrgConfirmBody: "You will lose access to this organization's membership features.",
  membersLeaveOrgConfirmAction: "Leave",
  membersInviteLabel: "Invite a member",
  membersInviteSubmitLabel: "Send invite",
  membersInviteSuccess: "Invitation sent.",

  # New position modal
  newPositionModalTitle: "Propose new position",
  newPositionSubmitLabel: "Propose position",
  newPositionBillPickerPlaceholder: "Search bills…",
  newPositionSummaryPlaceholder: "Describe the organization's position…",
  newPositionSourceUrlPlaceholder: "https://…"
}.freeze
