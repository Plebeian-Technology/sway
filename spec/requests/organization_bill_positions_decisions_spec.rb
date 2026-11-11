# frozen_string_literal: true

require "rails_helper"

# Approving, rejecting and editing a drafted organization position, one card at
# a time. Approve goes through OrganizationBillPositionsController#create;
# reject and edit go through BillDraftOrgPositionsController#update.
RSpec.describe "OrganizationBillPositionsDecisions", type: :request do
  include_context "SessionDouble"

  let(:bill) { create(:bill) }
  let!(:provisioning) do
    create(
      :bill_llm_provisioning,
      bill: bill,
      # @lat: [[testing-the-toolchain#A fixture has to describe a row the system could really produce]]
      extracted_testimony: "Testimony of Test Org, submitted in support.",
      draft_org_positions: [
        {"org_name" => "Test Org", "stance" => "support", "summary" => "We support this"}
      ]
    )
  end
  let(:organization) { create(:organization, sway_locale: bill.sway_locale) }
  # Composite id "<bill_id>-<index>" — index 0 points at the first draft entry.
  let(:draft_composite_id) { "#{bill.id}-0" }

  context "as admin" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    it "approve creates OBP + logs org_position_decision approved + normalises support 'support' to 'FOR'" do
      expect {
        post "/organization_bill_positions",
          params: {
            organization_bill_position: {
              positions: [
                {bill_id: bill.id, organization_id: organization.id, support: "support", summary: "Approved"}
              ]
            }
          }
      }.to change(OrganizationBillPosition, :count).by(1)
        .and change { PipelineActivityLogEntry.where(event_type: "org_position_decision").count }.by(1)

      entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").last
      expect(entry.payload["decision"]).to eq("approved")
      # The "support" the client sends MUST be turned into the stored value
      # "FOR", so this controller agrees with
      # BillsController#approve_org_position. Without the STANCE_TO_SUPPORT
      # map, the raw "support" string would go straight into the column.
      expect(OrganizationBillPosition.last.support).to eq("FOR")
    end

    it "approve normalises support 'oppose' to legacy 'AGAINST'" do
      post "/organization_bill_positions",
        params: {
          organization_bill_position: {
            positions: [
              {bill_id: bill.id, organization_id: organization.id, support: "oppose", summary: "We oppose"}
            ]
          }
        }
      expect(response).to have_http_status(:ok)
      expect(OrganizationBillPosition.last.support).to eq("AGAINST")
    end

    it "approve normalises support 'neutral' to legacy 'ABSTAIN'" do
      post "/organization_bill_positions",
        params: {
          organization_bill_position: {
            positions: [
              {bill_id: bill.id, organization_id: organization.id, support: "neutral", summary: "Neutral"}
            ]
          }
        }
      expect(response).to have_http_status(:ok)
      expect(OrganizationBillPosition.last.support).to eq("ABSTAIN")
    end

    it "approve passes legacy direct values ('FOR') through unchanged" do
      post "/organization_bill_positions",
        params: {
          organization_bill_position: {
            positions: [
              {bill_id: bill.id, organization_id: organization.id, support: "FOR", summary: "Already legacy"}
            ]
          }
        }
      expect(response).to have_http_status(:ok)
      expect(OrganizationBillPosition.last.support).to eq("FOR")
    end

    it "approve rejects unknown support values with 422 invalid_stance" do
      expect {
        post "/organization_bill_positions",
          params: {
            organization_bill_position: {
              positions: [
                {bill_id: bill.id, organization_id: organization.id, support: "garbage", summary: "Bad"}
              ]
            }
          }
      }.not_to change(OrganizationBillPosition, :count)
      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq("invalid_stance")
      # A nonsense value gets the explicit "Unknown support value" message.
      expect(body.dig("error", "message")).to match(/Unknown support value/i)
      expect(body.dig("error", "message")).to include("\"garbage\"")
    end

    # A missing `support` is a different problem from a nonsense one, so the
    # message has to point at the real fix: "must include a support" rather
    # than "Unknown support value <garbage>". Both used to come out as
    # `Unknown support value ""`, which read like a typo or an escaping bug.
    it "approve rejects a missing `support` value with a missing-stance message (LOW-2)" do
      expect {
        post "/organization_bill_positions",
          params: {
            organization_bill_position: {
              positions: [
                {bill_id: bill.id, organization_id: organization.id, summary: "no stance"}
              ]
            }
          }
      }.not_to change(OrganizationBillPosition, :count)
      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body.dig("error", "code")).to eq("invalid_stance")
      expect(body.dig("error", "message")).to match(/must include a `support` value/i)
    end

    # @lat: [[replace-bill-org-positions-service-design#Why the bill id is validated before anything is touched]]
    describe "MEDIUM-4 bill_id presence" do
      it "returns 422 missing_bill_id when no position declares a bill_id" do
        expect {
          post "/organization_bill_positions",
            params: {
              organization_bill_position: {
                positions: [
                  {organization_id: organization.id, support: "support", summary: "x"}
                ]
              }
            }
        }.not_to change(OrganizationBillPosition, :count)
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "code")).to eq("missing_bill_id")
      end

      it "returns 404 bill_not_found when bill_id references a non-existent bill" do
        expect {
          post "/organization_bill_positions",
            params: {
              organization_bill_position: {
                positions: [
                  {bill_id: 999_999, organization_id: organization.id, support: "support", summary: "x"}
                ]
              }
            }
        }.not_to change(OrganizationBillPosition, :count)
        expect(response).to have_http_status(:not_found)
        body = JSON.parse(response.body)
        expect(body.dig("error", "code")).to eq("bill_not_found")
      end

      it "returns 422 mixed_bill_ids when positions declare more than one bill_id" do
        second_bill = create(:bill)
        expect {
          post "/organization_bill_positions",
            params: {
              organization_bill_position: {
                positions: [
                  {bill_id: bill.id, organization_id: organization.id, support: "support", summary: "x"},
                  {bill_id: second_bill.id, organization_id: organization.id, support: "oppose", summary: "y"}
                ]
              }
            }
        }.not_to change(OrganizationBillPosition, :count)
        expect(response).to have_http_status(:unprocessable_content)
        body = JSON.parse(response.body)
        expect(body.dig("error", "code")).to eq("mixed_bill_ids")
      end
    end

    it "reject removes draft + logs org_position_decision rejected" do
      # Rejecting really deletes the draft entry; it used to only mark it with
      # `entry["rejected"] = true`. So after a rejection the
      # draft_org_positions array no longer holds that entry at all.
      starting_count = provisioning.draft_org_positions.size
      patch "/bill_draft_org_positions/#{draft_composite_id}",
        params: {rejected: true, draft_org_name: "Test Org"}
      provisioning.reload
      expect(provisioning.draft_org_positions.size).to eq(starting_count - 1)
      entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").last
      expect(entry.payload["decision"]).to eq("rejected")
    end

    it "edit updates draft + logs org_position_decision edited" do
      patch "/bill_draft_org_positions/#{draft_composite_id}",
        params: {stance: "oppose", draft_org_name: "Test Org"}
      provisioning.reload
      expect(provisioning.draft_org_positions.first["stance"]).to eq("oppose")
      entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").last
      expect(entry.payload["decision"]).to eq("edited")
    end

    # @lat: [[bill-draft-org-positions-controller#Why the success notice names the bill and organization]]
    it "reject flash notice names the org and bill external_id" do
      patch "/bill_draft_org_positions/#{draft_composite_id}",
        params: {rejected: true, draft_org_name: "Test Org"}
      expect(flash[:notice]).to eq("Rejected Test Org on #{bill.external_id}.")
    end

    it "edit flash notice names the org and bill external_id" do
      patch "/bill_draft_org_positions/#{draft_composite_id}",
        params: {stance: "oppose", draft_org_name: "Test Org"}
      expect(flash[:notice]).to eq("Updated Test Org on #{bill.external_id}.")
    end

    describe "news-sourced draft organization positions" do
      let(:news_article) { create(:news_article, article_kind: "reporting") }
      let(:article_text) do
        "\"We strongly support this legislation to safeguard fair housing for all tenants,\" " \
          "said Jane Doe, Executive Director of Baltimore Tenants Union."
      end
      let(:text_version) do
        create(
          :news_article_text_version,
          news_article: news_article,
          extraction_status: "extracted",
          text: article_text
        )
      end
      let(:bna) do
        record = create(
          :bill_news_article,
          bill: bill,
          news_article: news_article,
          approved: true,
          approved_by: admin,
          approved_at: Time.current
        )
        record.update_columns(current_text_version_id: text_version.id)
        record
      end
      let(:excerpt) { "We strongly support this legislation to safeguard fair housing for all tenants" }
      let(:news_draft) do
        {
          "org_name" => "Baltimore Tenants Union",
          "stance" => "support",
          "summary" => "Supports fair housing legislation for tenants.",
          "bill_news_article_id" => bna.id,
          "text_version_id" => text_version.id,
          "evidence_excerpt" => excerpt,
          "speaker_name" => "Jane Doe",
          "speaker_role" => "Executive Director",
          "source_url" => "https://example.com/article",
          "outlet_name" => "The Baltimore Banner",
          "article_title" => "Tenants Fight for Fair Housing",
          "excerpt_offset" => 1,
          "excerpt_length" => excerpt.length,
          "excerpt_paragraph" => 1,
          "excerpt_page" => 1
        }
      end

      before do
        provisioning.update!(
          extracted_testimony: nil,
          supplemental_testimony: nil,
          draft_org_positions: [news_draft]
        )
      end

      it "preserves news provenance fields when editing org_name, stance, or summary via PATCH /bill_draft_org_positions/:id" do
        expected_provenance = news_draft.except("org_name", "stance", "summary")

        patch "/bill_draft_org_positions/#{draft_composite_id}",
          params: {
            org_name: "Baltimore Tenants Union Coalition",
            stance: "oppose",
            summary: "Updated news stance summary.",
            draft_org_name: "Baltimore Tenants Union"
          }

        expect(response).to redirect_to(positions_bill_creator_path(id: bill.id))
        updated_entry = provisioning.reload.draft_org_positions.first
        expect(updated_entry["org_name"]).to eq("Baltimore Tenants Union Coalition")
        expect(updated_entry["stance"]).to eq("oppose")
        expect(updated_entry["summary"]).to eq("Updated news stance summary.")
        expect(updated_entry.slice(*expected_provenance.keys)).to eq(expected_provenance)
      end

      it "approves a grounded news-sourced draft on a bill with no hearing testimony via POST /bills/:id/approve_org_position" do
        expect {
          post "/bills/#{bill.id}/approve_org_position",
            params: {
              org_name: "Baltimore Tenants Union",
              support: "support",
              summary: "Supports fair housing legislation for tenants.",
              index: 0,
              draft_org_name: "Baltimore Tenants Union"
            }
        }.to change(Organization, :count).by(1)
          .and change(OrganizationBillPosition, :count).by(1)
          .and change { PipelineActivityLogEntry.where(event_type: "org_position_decision").count }.by(1)

        expect(response).to redirect_to(positions_bill_creator_path(bill))
        expect(provisioning.reload.draft_org_positions).to eq([])
        org = Organization.find_by(name: "Baltimore Tenants Union", sway_locale: bill.sway_locale)
        position = OrganizationBillPosition.find_by(bill: bill, organization: org)
        expect(position&.support).to eq("FOR")
        expect(position&.ai_summary).to be_nil
      end

      it "redirects with an Inertia org_position error when the matched Organization has a UserOrganizationMembership" do
        org = create(:organization, name: "Baltimore Tenants Union", sway_locale: bill.sway_locale)
        create(:user_organization_membership, organization: org, user: admin)

        expect {
          post "/bills/#{bill.id}/approve_org_position",
            params: {
              org_name: "Baltimore Tenants Union",
              support: "support",
              summary: "Supports fair housing legislation for tenants.",
              index: 0,
              draft_org_name: "Baltimore Tenants Union"
            }
        }.not_to change(OrganizationBillPosition, :count)

        expect(response).to redirect_to(positions_bill_creator_path(bill))
        errors = session[:inertia_errors] || {}
        expect(errors[:org_position] || errors["org_position"]).to match(/registered user accounts/i)
      end

      it "redirects with an Inertia org_position error when the backing BillNewsArticle has been unapproved" do
        bna.update_columns(approved: false)

        expect {
          post "/bills/#{bill.id}/approve_org_position",
            params: {
              org_name: "Baltimore Tenants Union",
              support: "support",
              summary: "Supports fair housing legislation for tenants.",
              index: 0,
              draft_org_name: "Baltimore Tenants Union"
            }
        }.not_to change(OrganizationBillPosition, :count)

        expect(response).to redirect_to(positions_bill_creator_path(bill))
        errors = session[:inertia_errors] || {}
        expect(errors[:org_position] || errors["org_position"]).to match(/retracted/i)
      end
    end
  end

  describe "PATCH /bill_draft_org_positions/:id admin guard" do
    include_examples "requires sway admin",
      verb: :patch,
      path: "/bill_draft_org_positions/0-0",
      params: {rejected: true}
  end
end
