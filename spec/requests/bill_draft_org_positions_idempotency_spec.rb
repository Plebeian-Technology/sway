# frozen_string_literal: true

require "rails_helper"

# @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller]]
RSpec.describe "BillDraftOrgPositions reject idempotency",
  type: :request do
  include_context "SessionDouble"

  # @lat: [[admin-gate-shared-examples#Admin-gate shared examples#Admin refusal must precede resource lookup]]
  before do
    session_hash[:user_id] = admin.id
    create(
      :bill_llm_provisioning,
      :with_diff_content,
      bill: bill,
      generation_status: "completed",
      llm_summary: "Test summary",
      llm_full_breakdown: "## Test",
      # @lat: [[testing-the-toolchain#A fixture has to describe a row the system could really produce]]
      extracted_testimony: "Testimony of Sole Org, submitted at the hearing.",
      draft_org_positions: [
        {"org_name" => "Sole Org", "stance" => "support", "summary" => "Supports."}
      ]
    )
  end

  let(:admin) { create(:user, :sway_admin) }
  let(:bill) { create(:bill) }

  include_examples "requires sway admin",
    verb: :patch,
    path: "/bill_draft_org_positions/1-0",
    params: {rejected: true}

  # @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller#Draft identity separates a moved entry from a removed one]]
  def sole_org_identity(kind)
    return {draft_org_name: "Sole Org"} if kind == :name_only

    entry = bill.bill_llm_provisioning.reload.draft_org_positions.first
    {draft_org_name: "Sole Org", draft_token: BillLlmProvisioning.draft_token(entry)}
  end

  [:name_only, :name_and_token].each do |identity|
    context "when the caller names the draft by #{identity}" do
      it "first reject removes the draft and redirects with descriptive notice" do
        patch "/bill_draft_org_positions/#{bill.id}-0",
          params: {rejected: true}.merge(sole_org_identity(identity))
        expect(response).to have_http_status(:found)
        expect(flash[:notice]).to eq("Rejected Sole Org on #{bill.external_id}.")
        expect(bill.bill_llm_provisioning.reload.draft_org_positions).to eq([])
      end

      it "duplicate reject against an out-of-bounds index is a 302 no-op (NOT 404)" do
        # Act out the fast double-click: the first PATCH went through and emptied the list,
        # and the second arrives aimed at the same, now-stale, index.
        params = {rejected: true}.merge(sole_org_identity(identity))
        bill.bill_llm_provisioning.update!(
          draft_org_positions: [] #: Array[untyped]
        )

        patch "/bill_draft_org_positions/#{bill.id}-0", params: params

        expect(response).to have_http_status(:found),
          "expected idempotent reject to redirect 302; got #{response.status} #{response.body}"
        expect(flash[:notice]).to eq("Draft already removed.")
      end

      # @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller#Draft identity separates a moved entry from a removed one]]
      it "tells the operator the list moved, without asking them to reload" do
        patch "/bill_draft_org_positions/#{bill.id}-99",
          params: {rejected: true}.merge(sole_org_identity(identity))

        # @lat: [[toasts#Toasts#Flash toast dedupe#A refusal that arrives in the errors hash needs its own reader]]
        expect(response).to redirect_to(positions_bill_creator_path(id: bill.id))
        expect(session[:inertia_errors]).to include(:org_position)
        expect(session[:inertia_errors][:org_position]).to eq(DraftOrgPositionRefusals::LIST_CHANGED)
        expect(session[:inertia_errors][:org_position]).not_to match(/reload|refresh/i)
        expect(flash[:notice]).to be_nil
        expect(bill.bill_llm_provisioning.reload.draft_org_positions.length).to eq(1)
      end

      it "still says already removed when the named draft is nowhere in the list" do
        # The real double-click: the first reject took "Sole Org" out, so nothing in
        # the array answers to that name any more.
        params = {rejected: true}.merge(sole_org_identity(identity))
        bill.bill_llm_provisioning.update!(
          draft_org_positions: [] #: Array[untyped]
        )

        patch "/bill_draft_org_positions/#{bill.id}-99", params: params

        expect(response).to have_http_status(:found)
        expect(flash[:notice]).to eq("Draft already removed.")
      end
    end
  end

  it "edit branch against a draft that is really gone still 404s (real client error)" do
    # The forgiving behaviour is for rejecting only. An edit aimed at nothing has to
    # raise a real error rather than quietly do nothing.
    bill.bill_llm_provisioning.update!(
      draft_org_positions: [] #: Array[untyped]
    )

    patch "/bill_draft_org_positions/#{bill.id}-99",
      params: {stance: "oppose", summary: "should not stick", draft_org_name: "Sole Org"}

    expect(response).to have_http_status(:not_found)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("draft_not_found")
  end

  # Identity is asked for before the bounds now, so a request that names no
  # draft is refused whether or not its index is in range. It used to reach the
  # 404 above, which answered a question the caller had no business asking:
  # whether that index exists.
  it "refuses an out-of-range request that names no draft at all" do
    patch "/bill_draft_org_positions/#{bill.id}-99", params: {stance: "oppose"}

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["error"]).to eq("identity_required")
  end

  # @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller#Composite ids address one entry in the stored array]]
  it "refuses an id that is not '<bill_id>-<index>'" do
    patch "/bill_draft_org_positions/abc-xyz", params: {rejected: true, draft_org_name: "Sole Org"}

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["error"]).to eq("malformed_composite_id")
    expect(JSON.parse(response.body)["message"]).to match(/<bill_id>-<index>/)
  end

  it "refuses a bill that has no provisioning row" do
    # scheduled_release_date_utc set explicitly: the bills table carries a
    # UNIQUE index on (scheduled_release_date_utc, sway_locale_id), and the
    # factory's default would collide with `bill` above.
    other = create(:bill, scheduled_release_date_utc: 30.days.from_now.to_date)

    patch "/bill_draft_org_positions/#{other.id}-0", params: {rejected: true, draft_org_name: "Sole Org"}

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body)["error"]).to eq("no_provisioning_row")
  end

  # @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller#Draft edits are validated at the controller boundary]]
  describe "the stance an edit may store" do
    it "refuses a stance the schema does not allow, and names the ones it does" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {stance: "sympathetic", draft_org_name: "Sole Org"}

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("invalid_stance")
      expect(body["message"]).to include("support", "oppose", "neutral")
      # The stored stance is untouched — the fixture's own value, not the one
      # the request tried to write.
      expect(bill.bill_llm_provisioning.reload.draft_org_positions.first["stance"]).to eq("support")
    end

    # The legacy column values are a real vocabulary elsewhere
    # (OrganizationBillPosition.STANCE_TO_SUPPORT accepts them), and they are
    # still wrong HERE: the drafts array stores the schema's three words, and
    # the card cannot draw "FOR".
    it "refuses the legacy support-column spelling too" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {stance: "FOR", draft_org_name: "Sole Org"}

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to eq("invalid_stance")
    end

    it "still stores each of the three the schema allows" do
      BillLlmProvisioning::DRAFT_STANCES.each do |stance|
        patch "/bill_draft_org_positions/#{bill.id}-0",
          params: {stance: stance, draft_org_name: "Sole Org"}

        expect(response).to have_http_status(:found)
        expect(bill.bill_llm_provisioning.reload.draft_org_positions.first["stance"]).to eq(stance)
      end
    end
  end

  # The same gap as the stance check, one field over. The schema bounds the two
  # free-text fields for every other writer; this branch merged whatever the
  # request carried, so nothing stood between a request and a megabyte of text
  # in a serialized JSON column that every later read of this bill loads whole.
  describe "how much text an edit may store" do
    BillLlmProvisioning::DRAFT_TEXT_MAX_CHARS.each do |field, cap|
      it "refuses a #{field} longer than the schema allows, and names the cap" do
        stored = bill.bill_llm_provisioning.reload.draft_org_positions.first

        patch "/bill_draft_org_positions/#{bill.id}-0",
          params: {field => "x" * (cap + 1), :draft_org_name => "Sole Org"}

        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body["error"]).to eq("value_too_long")
        expect(body["message"]).to include(field, cap.to_s)
        expect(bill.bill_llm_provisioning.reload.draft_org_positions.first).to eq(stored)
      end

      it "stores a #{field} exactly at the cap" do
        patch "/bill_draft_org_positions/#{bill.id}-0",
          params: {field => "x" * cap, :draft_org_name => "Sole Org"}

        expect(response).to have_http_status(:found)
        expect(bill.bill_llm_provisioning.reload.draft_org_positions.first[field]).to eq("x" * cap)
      end
    end

    # No minimum is checked here on purpose. Clearing a summary is an ordinary
    # step while rewriting one, and a blank value cannot reach the public
    # record — ApproveOrgPositionService refuses one before it writes anything.
    it "still stores a cleared summary" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {summary: "", draft_org_name: "Sole Org"}

      expect(response).to have_http_status(:found)
      expect(bill.bill_llm_provisioning.reload.draft_org_positions.first["summary"]).to eq("")
    end

    # An edit that changes only the summary must not be caught by a check on a
    # field it never sent.
    it "leaves an edit that sends no stance alone" do
      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {summary: "reworded", draft_org_name: "Sole Org"}

      expect(response).to have_http_status(:found)
      expect(bill.bill_llm_provisioning.reload.draft_org_positions.first["summary"]).to eq("reworded")
    end
  end

  # @lat: [[bill-draft-org-position-controller#Bill draft organization-position controller#Non-admin rejection is checked for both response and stored state]]
  context "when a non-admin attempts to reject a draft" do
    it "leaves draft_org_positions untouched and redirects to root" do
      non_admin = create(:user)
      complete_registration_with_active_link(non_admin)
      session_hash[:user_id] = non_admin.id

      expect(bill.bill_llm_provisioning.reload.draft_org_positions.length).to eq(1)

      patch "/bill_draft_org_positions/#{bill.id}-0",
        params: {rejected: true, draft_org_name: "Sole Org"}

      expect(response).to redirect_to(root_path)
      expect(bill.bill_llm_provisioning.reload.draft_org_positions.length).to eq(1)
    end
  end
end
