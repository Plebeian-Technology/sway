# frozen_string_literal: true

require "rails_helper"

# POST /bills/:id/paste_summary serves two kinds of caller, and this spec
# covers both. The mobile app gets JSON: 200 or 422 with a structured body.
# The web app gets an Inertia redirect carrying either flash[:paste_summary]
# or an errors hash.
RSpec.describe "BillsPasteSummary", type: :request do
  include_context "SessionDouble"
  include ActiveSupport::Testing::TimeHelpers

  let(:bill) { create(:bill) }
  # @lat: [[paste-summary-draft-positions-testimony-guard#Why a non-empty list requires testimony]]
  let!(:provisioning) do
    create(:bill_llm_provisioning, bill: bill, extracted_testimony: "Testimony of Test Org in support.")
  end
  let(:valid_payload) do
    {
      summary_markdown: "Brief one-line summary",
      full_breakdown_markdown: "## Section 1\nDetails",
      draft_org_positions: [
        {org_name: "Test Org", stance: "support", summary: "We support this bill"}
      ]
    }
  end
  let(:valid_json) { JSON.generate(valid_payload) }
  # Fails the schema: `summary_markdown` is missing. It is now the only
  # required key, since draft_org_positions was made optional.
  let(:invalid_json) { JSON.generate(draft_org_positions: []) }

  include_examples "requires sway admin",
    verb: :post,
    path: "/bills/0/paste_summary",
    params: {summary_json: "{}"}

  context "as admin" do
    let(:admin) { create(:user, :sway_admin) }

    before { session_hash[:user_id] = admin.id }

    describe "mobile JSON surface (round 2 review)" do
      # @lat: [[mobile-format-negotiation-design#Why paste-summary's mobile JSON spec asserts content type, not just body shape]]
      it "returns 200 with serialized bill on valid JSON" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: valid_json},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("application/json")
        body = JSON.parse(response.body)
        expect(body["bill"]).to be_a(Hash)
        expect(body["bill"]["id"]).to eq(bill.id)
        expect(PipelineActivityLogEntry.where(event_type: "paste_summary_accepted").count).to eq(1)
        provisioning.reload
        expect(provisioning.llm_summary).to eq(valid_payload[:summary_markdown])
      end

      # @lat: [[paste-summary-bill-payload-serialization-choice#Why paste_summary_bill_payload uses to_sway_json]]
      it "ships draft_org_positions through the same projection the Inertia path uses" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: valid_json},
          headers: {"Accept" => "application/json"}

        drafts = JSON.parse(response.body).dig("bill", "bill_llm_provisioning", "draft_org_positions")
        expect(drafts.length).to eq(1)
        expect(drafts.first["draft_token"]).to be_present
        expect(drafts.first["draft_token"])
          .to eq(provisioning.reload.draft_org_positions_for_client.first["draft_token"])
      end

      # @lat: [[paste-summary-bill-payload-serialization-choice#Why paste_summary_bill_payload uses to_sway_json]]
      it "sends the same provisioning key set as the Inertia path" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: valid_json},
          headers: {"Accept" => "application/json"}

        keys = JSON.parse(response.body).dig("bill", "bill_llm_provisioning").keys
        expect(keys).to match_array(provisioning.reload.to_sway_json.keys.map(&:to_s))
      end

      it "tells the client the row has testimony behind its drafts, and how the run ended" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: valid_json},
          headers: {"Accept" => "application/json"}

        payload = JSON.parse(response.body).dig("bill", "bill_llm_provisioning")
        expect(payload["has_testimony"]).to be(true)
        expect(payload["generation_status"]).to eq("completed")
      end

      it "returns 422 with structured errors on schema-invalid JSON" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: invalid_json},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("application/json")
        body = JSON.parse(response.body)
        expect(body["error"]["code"]).to eq("validation_failed")
        expect(body["error"]["details"]["errors"]).to all(include("path", "message"))
        expect(PipelineActivityLogEntry.where(event_type: "paste_summary_rejected").count).to eq(1)
      end

      it "returns 422 on malformed JSON" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: "{not json"},
          headers: {"Accept" => "application/json"}
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.media_type).to eq("application/json")
        body = JSON.parse(response.body)
        expect(body["error"]["code"]).to eq("validation_failed")
        expect(PipelineActivityLogEntry.where(event_type: "paste_summary_rejected").count).to eq(1)
      end
    end

    describe "web Inertia surface (round 2 review)" do
      it "redirects to bill edit with flash[:paste_summary] = :persisted on success" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: valid_json}
        expect(response).to redirect_to(summary_bill_creator_path(id: bill.id))
        expect(flash[:paste_summary]).to eq(:persisted).or eq("persisted")
      end

      # @lat: [[paste-summary-audit-transaction-boundaries#settlement_still_expected?: full reasoning (superseding the note above)]]
      it "tells the operator when the paste saved but the status did not move" do
        provisioning.update!(generation_status: "failed", generation_error: "claude transport: 429")
        allow(SwayLogging).to receive(:warn)
        # @lat: [[paste-summary-audit-transaction-boundaries#Why the settle-failure spec stubs settle_pasted_row! by name]]
        allow_any_instance_of(PasteSummaryService).to receive(:settle_pasted_row!)
          .and_raise(ActiveRecord::LockWaitTimeout.new("database is locked"))

        post "/bills/#{bill.id}/paste_summary", params: {summary_json: valid_json}

        expect(response).to redirect_to(summary_bill_creator_path(id: bill.id))
        expect(flash[:paste_summary]).to eq(:persisted).or eq("persisted")
        expect(flash[:alert]).to include("paste it again to finish")
        expect(provisioning.reload.llm_summary).to eq("Brief one-line summary")
      end

      it "raises no alert on an ordinary paste" do
        post "/bills/#{bill.id}/paste_summary", params: {summary_json: valid_json}

        expect(flash[:alert]).to be_nil
      end

      # @lat: [[bill-paste-summary-response-outcomes#Why a redirect alone can't distinguish acceptance from refusal on the web path]]
      it "redirects WITHOUT accepting anything on schema-invalid JSON" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: invalid_json}

        expect(response).to redirect_to(summary_bill_creator_path(id: bill.id))
        expect(flash[:paste_summary]).to be_nil
        expect(provisioning.reload.llm_summary).to be_nil
      end

      # Validation errors used to land on the shared Inertia `errors` prop.
      # They now go into their own `flash[:paste_summary_errors]` slot. These
      # examples pin that down, so a slide back to the shared prop fails the
      # build instead of quietly satisfying the plain redirect check above.
      it "writes flash[:paste_summary_errors] on schema-invalid JSON" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: invalid_json}
        expect(response).to redirect_to(summary_bill_creator_path(id: bill.id))
        errors = flash[:paste_summary_errors]
        expect(errors).to be_an(Array)
        expect(errors).not_to be_empty
        # The controller writes Symbol keys ({path:, message:}). On a real
        # visit the flash travels through the session cookie and those keys
        # come back as strings, but in a request spec the hash stays in memory
        # and keeps the Symbols. Use indifferent access so both forms pass.
        first = errors.first.with_indifferent_access
        expect(first["path"]).to be_a(String)
        expect(first["message"]).to be_a(String)
      end

      it "writes flash[:paste_summary_errors] with `/` path on malformed JSON" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: "{not json"}
        flash_errors = flash[:paste_summary_errors].map { |e| e.with_indifferent_access }
        expect(flash_errors).to include(
          a_hash_including("path" => "/", "message" => /Invalid JSON/)
        )
      end

      it "does NOT pollute the global Inertia errors prop on schema-invalid JSON" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: invalid_json}
        # session[:inertia_errors] is how inertia-rails carries the shared
        # errors prop. Check that no top-level "/" key leaks into it, which is
        # what the old bug looked like.
        inertia_errors = session[:inertia_errors] || {}
        expect(inertia_errors.keys).not_to include("/")
      end

      it "does NOT pollute the global Inertia errors prop on malformed JSON" do
        post "/bills/#{bill.id}/paste_summary",
          params: {summary_json: "{not json"}
        inertia_errors = session[:inertia_errors] || {}
        expect(inertia_errors.keys).not_to include("/")
      end
    end

    # @lat: [[paste-summary-attrs-design#The attrs hash: one field at a time]]
    describe "operator_paste audit stamps (UAT Test 4)" do
      it "stamps llm_generated_at on accepted paste" do
        before_post = Time.current
        post "/bills/#{bill.id}/paste_summary", params: {summary_json: valid_json}
        after_post = Time.current
        provisioning.reload
        expect(provisioning.llm_generated_at).to be_between(before_post, after_post)
      end

      it "stamps llm_provider=operator_paste on accepted paste" do
        post "/bills/#{bill.id}/paste_summary", params: {summary_json: valid_json}
        provisioning.reload
        expect(provisioning.llm_provider).to eq("operator_paste")
      end

      it "advances llm_generated_at on each successful paste so the FE remount key changes" do
        post "/bills/#{bill.id}/paste_summary", params: {summary_json: valid_json}
        first_stamp = provisioning.reload.llm_generated_at
        expect(first_stamp).to be_present

        # @lat: [[paste-summary-attrs-design#The attrs hash: one field at a time]]
        second_payload = valid_payload.merge(summary_markdown: "Updated summary")
        travel_to(1.minute.from_now) do
          post "/bills/#{bill.id}/paste_summary", params: {summary_json: JSON.generate(second_payload)}
        end
        second_stamp = provisioning.reload.llm_generated_at
        expect(second_stamp).to be > first_stamp
      end

      it "does NOT touch llm_generated_at or llm_provider on rejected paste" do
        provisioning.update_columns(
          llm_generated_at: Time.zone.parse("2020-01-01 00:00:00 UTC"),
          llm_provider: "llamacpp"
        )
        post "/bills/#{bill.id}/paste_summary", params: {summary_json: invalid_json}
        provisioning.reload
        expect(provisioning.llm_generated_at).to eq(Time.zone.parse("2020-01-01 00:00:00 UTC"))
        expect(provisioning.llm_provider).to eq("llamacpp")
      end
    end

    # Now that bill_summary.json lists fewer required keys, data can be lost
    # without anyone noticing unless PasteSummaryService decides what to write
    # based on whether a key is PRESENT, not on whether its value looks truthy.
    describe "draft_org_positions omission guard (REVIEWS C7)" do
      let(:existing_positions) do
        [{"org_name" => "Existing Org", "stance" => "oppose", "summary" => "Prior draft."}]
      end

      it "leaves persisted draft_org_positions unchanged when the pasted body omits the key" do
        provisioning.update!(draft_org_positions: existing_positions)
        payload_without_positions = {summary_markdown: "New summary, no positions key"}
        post "/bills/#{bill.id}/paste_summary", params: {summary_json: JSON.generate(payload_without_positions)}
        expect(response).to have_http_status(:redirect)
        provisioning.reload
        expect(provisioning.draft_org_positions).to eq(existing_positions)
        expect(provisioning.llm_summary).to eq("New summary, no positions key")
      end

      it "clears persisted draft_org_positions when the pasted body includes an explicit empty array" do
        provisioning.update!(draft_org_positions: existing_positions)
        payload_with_explicit_empty = {summary_markdown: "New summary", draft_org_positions: []}
        post "/bills/#{bill.id}/paste_summary", params: {summary_json: JSON.generate(payload_with_explicit_empty)}
        expect(response).to have_http_status(:redirect)
        provisioning.reload
        expect(provisioning.draft_org_positions).to eq([])
      end
    end

    describe "Validate manual news summary publication paste gating" do
      it "rejects paste with news_usage: 'none' containing visible news citations" do
        payload = {
          summary_markdown: "## Summary\nCiting [News](https://baltimorebanner.com/article).",
          news_usage: "none"
        }
        post "/bills/#{bill.id}/paste_summary", params: {summary_json: JSON.generate(payload)}
        expect(response).to have_http_status(:redirect)
        follow_redirect!
        expect(flash[:paste_summary_errors]).to be_present
        expect(flash[:paste_summary_errors].first[:message]).to include("no-news usage")
      end

      it "paste with news_usage: 'cited' and source_uses captures snapshot on draft revision" do
        news_article = create(:news_article, canonical_url: "https://baltimoresun.com/report")
        text_version = create(:news_article_text_version, :extracted, news_article: news_article, text: "Report text verbatim.")
        bna = create(:bill_news_article, :approved, bill: bill, news_article: news_article, current_text_version: text_version)

        payload = {
          summary_markdown: "## Summary\nClaim text [Source](https://baltimoresun.com/report).",
          news_usage: "cited",
          source_uses: [
            {
              bill_news_article_id: bna.id,
              text_version_id: text_version.id,
              claim_text: "Claim text",
              evidence_excerpt: "Report text verbatim.",
              citation_url: "https://baltimoresun.com/report"
            }
          ]
        }
        post "/bills/#{bill.id}/paste_summary", params: {summary_json: JSON.generate(payload)}
        expect(response).to have_http_status(:redirect)

        latest_rev = bill.bill_summary_revisions.order(:id).last
        expect(latest_rev.publication_role).to eq("draft")
        expect(latest_rev.news_source_snapshot_id).to be_present
        expect(latest_rev.news_source_snapshot.source_uses.count).to eq(1)
      end
    end
  end
end
