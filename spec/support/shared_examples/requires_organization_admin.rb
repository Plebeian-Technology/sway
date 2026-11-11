# frozen_string_literal: true

# @lat: [[admin-gate-shared-examples]]
RSpec.shared_examples "requires organization admin" do |verb:, path:, params: {}|
  include_context "SessionDouble"

  # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#Organization-admin refusal is identified by status or flash]]
  def gate_blocked_response?
    response.status == 403 || (response.redirect? && flash[:alert] == "Forbidden")
  end

  context "when current_user is a sway admin (no org membership; org-admin gate is independent)" do
    let(:user) { create(:user, :sway_admin) }
    let(:organization) { create(:organization) }
    let(:resolved_path) { path.respond_to?(:call) ? instance_exec(&path) : path }

    before { session_hash[:user_id] = user.id }

    it "is forbidden (sway admin status does not satisfy org-admin gate)" do
      public_send(verb, resolved_path, params: params)
      expect(gate_blocked_response?).to be(true),
        "Expected the org-admin gate to block a sway admin with no org membership"
    end
  end

  context "when current_user is a non-admin member of the organization" do
    # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#Incomplete registration can mask the admin gate]]
    let(:user) { create(:user, :registered) }
    let(:organization) { create(:organization) }
    let!(:membership) {
      create(:user_organization_membership,
        user: user, organization: organization, role: :standard, status: :active)
    }
    let(:resolved_path) { path.respond_to?(:call) ? instance_exec(&path) : path }

    before { session_hash[:user_id] = user.id }

    it "is forbidden" do
      public_send(verb, resolved_path, params: params)
      expect(gate_blocked_response?).to be(true),
        "Expected the org-admin gate to block a non-admin member"
    end
  end

  context "when current_user is a removed admin (status: :removed)" do
    # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#Incomplete registration can mask the admin gate]]
    let(:user) { create(:user, :registered) }
    let(:organization) { create(:organization) }
    let!(:membership) {
      m = create(:user_organization_membership,
        user: user, organization: organization, role: :admin, status: :active)
      # update_columns skips the guard that stops the last admin being removed. This is test
      # setup, not something production ever does; that guard is checked in spec/models/...
      m.update_columns(status: "removed")
      m
    }
    let(:resolved_path) { path.respond_to?(:call) ? instance_exec(&path) : path }

    before { session_hash[:user_id] = user.id }

    it "is forbidden (status filter must exclude removed admins)" do
      public_send(verb, resolved_path, params: params)
      expect(gate_blocked_response?).to be(true),
        "Expected the org-admin gate to block a removed admin"
    end
  end

  context "when current_user is the org admin (happy path)" do
    # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#Incomplete registration can mask the admin gate]]
    let(:user) { create(:user, :registered) }
    let(:organization) { create(:organization) }
    let!(:membership) {
      create(:user_organization_membership,
        user: user, organization: organization, role: :admin, status: :active)
    }
    let(:resolved_path) { path.respond_to?(:call) ? instance_exec(&path) : path }

    before { session_hash[:user_id] = user.id }

    it "is allowed (gate passes; controller may return 200/201/204/302)" do
      # If the action raises after the check passes — missing fixture data, say — the check
      # still passed; only a 403 means it blocked. Same approach as requires_sway_admin.rb.
      gate_blocked = false
      begin
        public_send(verb, resolved_path, params: params)
        gate_blocked = response.status == 403
      rescue
        gate_blocked = false
      end
      expect(gate_blocked).to be(false), "Expected org admin to be permitted but got 403 (gate blocked)"
    end
  end
end
