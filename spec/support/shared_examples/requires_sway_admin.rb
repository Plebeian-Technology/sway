# frozen_string_literal: true

# @lat: [[admin-gate-shared-examples]]
RSpec.shared_examples "requires sway admin" do |verb:, path:, params: {}|
  include_context "SessionDouble"

  # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#The Sway admin gate has two refusal shapes]]
  def gate_blocked_response?
    response.status == 403 || (response.redirect? && response.redirect_url == root_url)
  end

  # The action can raise before any response is committed, so the failure
  # message must not assume `response` is present.
  def gate_outcome_description
    return "no response (the action raised)" if response.nil?

    response.redirect? ? "#{response.status} -> #{response.redirect_url}" : response.status.to_s
  end

  context "when user is not a sway admin" do
    before do
      user = create(:user)
      create(:user_legislator, user: user)
      user.complete!
      session_hash[:user_id] = user.id
      session_hash[:auth_identity] = user.created_at.to_i
    end

    it "blocks the request at the admin gate" do
      public_send(verb, path, params: params)
      expect(gate_blocked_response?).to be(true),
        "Expected the admin gate to block a non-admin with a 403 or a redirect to " \
        "#{root_url}, got #{gate_outcome_description}"
    end
  end

  # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#Bearer authorization must replace any cookie identity]]
  context "when a bearer client is not a sway admin" do
    let(:bearer_raw_token) { "test-bearer-admin-gate-#{SecureRandom.hex(8)}" }

    before do
      session_hash.delete(:user_id)

      user = create(:user)
      create(:user_legislator, user: user)
      user.complete!
      ApiKey.create!(bearer: user, token: bearer_raw_token)
    end

    it "is refused with a JSON 403 carrying no Location header" do
      public_send(verb, path, params: params,
        headers: {"Authorization" => "Bearer #{bearer_raw_token}"})

      expect(response.status).to eq(403),
        "Expected the admin gate to answer a non-admin bearer client with 403, " \
        "got #{gate_outcome_description}"
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body).dig("error", "code")).to eq("forbidden")
      # A bearer client must never be redirected.
      expect(response.headers["Location"]).to be_nil
    end
  end

  context "when user is a sway admin" do
    before do
      admin = create(:user, :sway_admin)
      session_hash[:user_id] = admin.id
      session_hash[:auth_identity] = admin.created_at.to_i
    end

    it "permits the request (not blocked by the admin gate)" do
      # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#The permitted request must not swallow spec failures]]
      gate_blocked = false
      begin
        public_send(verb, path, params: params)
        gate_blocked = gate_blocked_response?
      rescue ::RSpec::Expectations::ExpectationNotMetError, ::RSpec::Mocks::MockExpectationError
        raise
      rescue
        gate_blocked = false
      end
      expect(gate_blocked).to be(false),
        "Expected admin to be permitted but the admin gate blocked the request " \
        "(#{gate_outcome_description})"
    end
  end
end
