# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::BillNewsArticles", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:bill) { create(:bill, sway_locale: sway_locale) }
  let(:other_bill) { create(:bill, sway_locale: sway_locale) }
  let(:news_article) { create(:news_article) }
  let(:bill_news_article) { create(:bill_news_article, bill: bill, news_article: news_article) }

  # --- Admin authorization guards ---
  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/bills/1/news_articles"

  include_examples "requires sway admin",
    verb: :post,
    path: "/admin/bills/1/news_articles"

  include_examples "requires sway admin",
    verb: :patch,
    path: "/admin/bills/1/news_articles/1",
    params: {approved: true}

  context "as an unauthenticated user" do
    it "redirects GET to root" do
      get "/admin/bills/#{bill.id}/news_articles"
      expect(response).to redirect_to(root_path)
    end

    it "redirects POST to root" do
      post "/admin/bills/#{bill.id}/news_articles"
      expect(response).to redirect_to(root_path)
    end

    it "redirects PATCH to root" do
      patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}", params: {approved: true}
      expect(response).to redirect_to(root_path)
    end
  end

  context "as an ordinary user" do
    let(:user) { create(:user) }

    before do
      complete_registration_with_active_link(user)
      session_hash[:user_id] = user.id
      session_hash[:auth_identity] = user.created_at.to_i
    end

    it "redirects GET to root" do
      get "/admin/bills/#{bill.id}/news_articles"
      expect(response).to redirect_to(root_path)
    end

    it "redirects POST retrieval to root without enqueuing jobs" do
      expect {
        post "/admin/bills/#{bill.id}/news_articles"
      }.not_to have_enqueued_job(NewsArticleTextFetchJob)
      expect(response).to redirect_to(root_path)
    end

    it "redirects PATCH review update to root" do
      patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}", params: {approved: true}
      expect(response).to redirect_to(root_path)
      expect(bill_news_article.reload.approved).to be(false)
    end
  end

  context "as an organization administrator (non-sway admin)" do
    before do
      org_admin = create(:user)
      organization = create(:organization, sway_locale: sway_locale)
      complete_registration_with_active_link(org_admin)
      create(:user_organization_membership, user: org_admin, organization: organization, role: "admin")
      session_hash[:user_id] = org_admin.id
      session_hash[:auth_identity] = org_admin.created_at.to_i
    end

    it "redirects PATCH to root" do
      patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}", params: {approved: true}
      expect(response).to redirect_to(root_path)
      expect(bill_news_article.reload.approved).to be(false)
    end
  end

  context "as a sway admin" do
    let(:admin) { create(:user, :sway_admin) }

    before do
      complete_registration_with_active_link(admin)
      session_hash[:user_id] = admin.id
      session_hash[:auth_identity] = admin.created_at.to_i
    end

    describe "GET /admin/bills/:bill_id/news_articles" do
      it "returns 200 with serialized bill news articles scoped to the bill" do
        bna = create(:bill_news_article, :with_text_version, bill: bill, news_article: news_article)
        other_bna = create(:bill_news_article, bill: other_bill)

        get "/admin/bills/#{bill.id}/news_articles"

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body).to be_an(Array)
        expect(body.size).to eq(1)

        expected_keys = %w[
          id bill_id news_article_id url title source_name domain author
          published_at approved review_version stance stance_version
          current_text_version_id has_text text_digest text_origin excerpt
          created_at updated_at match_kind article_kind
        ]
        expect(body.first.keys).to match_array(expected_keys)
        expect(body.first["id"]).to eq(bna.id)
        expect(body.first["bill_id"]).to eq(bill.id)
        expect(body.first["approved"]).to be(false)
        expect(body.pluck("id")).not_to include(other_bna.id)
      end
    end

    describe "POST /admin/bills/:bill_id/news_articles (explicit discovery)" do
      it "triggers explicit discovery and returns receipt status distinguishing retrieval failure from no coverage" do
        receipt = instance_double(
          NewsArticleDiscoveryRequest,
          status: "no_matches",
          diagnostics: [{"message" => "Zero matching articles found"}]
        )
        allow(BillNewsArticleFetchService).to receive(:call).with(bill: bill, requested_by: admin).and_return(receipt)

        post "/admin/bills/#{bill.id}/news_articles", headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["receipt_status"]).to eq("no_matches")
        expect(body["articles"]).to be_an(Array)
      end

      it "returns 422 when retrieval explicitly fails with transport or provider error" do
        receipt = instance_double(
          NewsArticleDiscoveryRequest,
          status: "failed",
          diagnostics: [{"error" => "Connection refused: provider timeout"}]
        )
        allow(BillNewsArticleFetchService).to receive(:call).with(bill: bill, requested_by: admin).and_return(receipt)

        post "/admin/bills/#{bill.id}/news_articles", headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:unprocessable_content)
        body = response.parsed_body
        expect(body["receipt_status"]).to eq("failed")
      end

      it "names the receipt's failure reason in the 422 answer to a bearer request" do
        receipt = instance_double(
          NewsArticleDiscoveryRequest,
          status: "failed",
          diagnostics: [{"error" => "Connection refused: provider timeout"}]
        )
        allow(BillNewsArticleFetchService).to receive(:call).with(bill: bill, requested_by: admin).and_return(receipt)

        post "/admin/bills/#{bill.id}/news_articles",
          headers: authenticate_as(admin).merge("Accept" => "application/json"),
          as: :json

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body).to include(
          "receipt_status" => "failed",
          "error" => "Connection refused: provider timeout"
        )
      end

      it "enqueues NewsArticleTextFetchJob and acquires immutable article text for matching candidates upon discovery" do
        NewsArticleRobotsPolicy.reset_cache!
        bill.update!(external_id: "24-0012", title: "Affordable Housing Act", introduced_date_time_utc: Time.zone.parse("2026-01-15 12:00:00"))

        allow(BraveSearch::Client).to receive(:configured?).and_return(true)
        brave_search_client = instance_double(BraveSearch::Client)
        allow(BraveSearch::Client).to receive(:new).and_return(brave_search_client)
        allow(brave_search_client).to receive(:search).and_return([
          {
            "url" => "https://www.thebanner.com/story",
            "title" => "Baltimore Council Advances Bill 24-0012 in 2026 Session",
            "cited_text" => "Discussion on affordable housing legislation in Baltimore City Council.",
            "match_kind" => "direct"
          }
        ])

        html_body = <<~HTML
          <!DOCTYPE html>
          <html>
            <head>
              <title>Baltimore Council Advances Bill 24-0012 in 2026 Session</title>
              <meta name="author" content="Jane Reporter">
              <meta property="article:published_time" content="2026-03-15T12:00:00Z">
            </head>
            <body>
              <article>
                <h1>Baltimore Council Advances Bill 24-0012 in 2026 Session</h1>
                <p>The Baltimore City Council voted on Monday to advance Bill 24-0012 on affordable housing.</p>
                <p>Proponents highlighted dedicated funding for neighborhood revitalization across the city.</p>
              </article>
            </body>
          </html>
        HTML
        stub_request(:get, "https://www.thebanner.com/robots.txt")
          .to_return(
            status: 200,
            headers: {"Content-Type" => "text/plain"},
            body: "User-agent: *\nAllow: /\n"
          )
        stub_request(:get, "https://www.thebanner.com/story")
          .to_return(
            status: 200,
            headers: {"Content-Type" => "text/html; charset=utf-8"},
            body: html_body
          )

        expect {
          post "/admin/bills/#{bill.id}/news_articles", headers: {"Accept" => "application/json"}
        }.to have_enqueued_job(NewsArticleTextFetchJob)

        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["receipt_status"]).to eq("succeeded")

        bna = bill.bill_news_articles.joins(:news_article).find_by!(news_articles: {canonical_url: "https://www.thebanner.com/story"})
        expect(NewsArticleTextFetchJob).to have_been_enqueued.with(bna.id)

        # Run the enqueued job to simulate worker processing
        NewsArticleTextFetchJob.new.perform(bna.id)

        version = bna.reload.current_text_version
        expect(version).to be_present
        expect(version.origin).to eq("retrieved")
        expect(version.extraction_status).to eq("extracted")
        expect(version.text).to include("The Baltimore City Council voted on Monday to advance Bill 24-0012 on affordable housing.")
        expect(version.digest).to eq(Digest::SHA256.hexdigest(version.text))
      end

      it "does not re-enqueue NewsArticleTextFetchJob or overwrite manual text when article already has a text version" do
        existing_article = create(:news_article, canonical_url: "https://www.thebanner.com/story")
        existing_bna = create(
          :bill_news_article,
          bill: bill,
          news_article: existing_article,
          approved: false,
          match_kind: "direct"
        )
        manual_version = NewsArticleTextVersion.create!(
          news_article: existing_article,
          origin: "manual",
          extraction_status: "extracted",
          text: "Existing manual text that must be preserved.",
          digest: Digest::SHA256.hexdigest("Existing manual text that must be preserved."),
          actor_id: admin.id
        )
        existing_bna.update!(current_text_version: manual_version)

        bill.update!(external_id: "24-0012", title: "Affordable Housing Act", introduced_date_time_utc: Time.zone.parse("2026-01-15 12:00:00"))
        allow(BraveSearch::Client).to receive(:configured?).and_return(true)
        brave_search_client = instance_double(BraveSearch::Client)
        allow(BraveSearch::Client).to receive(:new).and_return(brave_search_client)
        allow(brave_search_client).to receive(:search).and_return([
          {
            "url" => "https://www.thebanner.com/story",
            "title" => "Baltimore Council Advances Bill 24-0012 in 2026 Session",
            "cited_text" => "Discussion on affordable housing legislation in Baltimore City Council.",
            "match_kind" => "direct"
          }
        ])

        expect {
          post "/admin/bills/#{bill.id}/news_articles", headers: {"Accept" => "application/json"}
        }.not_to have_enqueued_job(NewsArticleTextFetchJob)

        expect(response).to have_http_status(:ok)
        expect(existing_bna.reload.current_text_version).to eq(manual_version)
        expect(existing_bna.current_text_version.text).to eq("Existing manual text that must be preserved.")
      end

      it "retries an existing discovery request idempotently preserving receipt identity and actor" do
        discovery_req = NewsArticleDiscoveryRequest.create!(
          bill: bill,
          requested_by: admin,
          status: "failed",
          source_config_digest: Digest::SHA256.hexdigest("config"),
          provider: "brave_search",
          model: "web_search",
          match_counts: {"direct" => 0, "context" => 0, "ambiguous" => 0, "unmatched" => 0},
          diagnostics: [{"error" => "previous timeout"}]
        )

        bill.update!(external_id: "24-0012", title: "Affordable Housing Act", introduced_date_time_utc: Time.zone.parse("2026-01-15 12:00:00"))
        allow(BraveSearch::Client).to receive(:configured?).and_return(true)
        brave_search_client = instance_double(BraveSearch::Client)
        allow(BraveSearch::Client).to receive(:new).and_return(brave_search_client)
        allow(brave_search_client).to receive(:search).and_return([
          {
            "url" => "https://www.thebanner.com/story",
            "title" => "Baltimore Council Advances Bill 24-0012 in 2026 Session",
            "cited_text" => "Discussion on affordable housing legislation in Baltimore City Council.",
            "match_kind" => "direct"
          }
        ])

        expect {
          post "/admin/bills/#{bill.id}/news_articles",
            params: {discovery_request_id: discovery_req.id},
            headers: {"Accept" => "application/json"}
        }.not_to change(NewsArticleDiscoveryRequest, :count)

        expect(response).to have_http_status(:ok)
        expect(discovery_req.reload.status).to eq("succeeded")
        expect(discovery_req.requested_by).to eq(admin)
        expect(discovery_req.completed_at).to be_present
      end

      it "returns 404 when discovery_request belongs to a different bill" do
        other_request = create(:news_article_discovery_request, bill: other_bill, requested_by: admin)

        post "/admin/bills/#{bill.id}/news_articles",
          params: {discovery_request_id: other_request.id},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:not_found)
      end

      it "returns 404 when bill does not exist" do
        expect {
          post "/admin/bills/-999999/news_articles", headers: {"Accept" => "application/json"}
        }.not_to have_enqueued_job(NewsArticleTextFetchJob)

        expect(response).to have_http_status(:not_found)
      end

      it "does not enqueue any jobs on GET /admin/bills/:bill_id/news_articles" do
        expect {
          get "/admin/bills/#{bill.id}/news_articles"
        }.not_to have_enqueued_job(NewsArticleTextFetchJob)

        expect(response).to have_http_status(:ok)
      end

      it "triggers explicit discovery via Inertia and redirects back to bill creator summary with 303" do
        receipt = instance_double(
          NewsArticleDiscoveryRequest,
          status: "succeeded",
          diagnostics: []
        )
        allow(BillNewsArticleFetchService).to receive(:call).with(bill: bill, requested_by: admin).and_return(receipt)

        post "/admin/bills/#{bill.id}/news_articles",
          headers: {
            "X-Inertia" => "true",
            "X-Inertia-Version" => InertiaRails.configuration.version.to_s
          }

        expect(response).to have_http_status(:see_other)
        expect(response).to redirect_to(summary_bill_creator_path(bill))

        follow_redirect!
        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props).to have_key(:news_articles)
      end
    end

    describe "GET /admin/bill_creator/new" do
      it "returns safe empty state for news_articles and receipt_status without querying news tables" do
        queries = []
        ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _start, _finish, _id, payload|
          queries << payload[:sql] unless payload[:cached] || payload[:name] == "SCHEMA"
        end

        get "/admin/bill_creator/new",
          headers: {
            "X-Inertia" => "true",
            "X-Inertia-Version" => InertiaRails.configuration.version.to_s
          }

        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props[:news_articles]).to eq([])
        expect(inertia.props[:receipt_status]).to be_nil

        news_queries = queries.select { |q| q =~ /news_articles|bill_news_articles|news_article_discovery_requests/i }
        expect(news_queries).to be_empty
      end
    end

    describe "PATCH /admin/bills/:bill_id/news_articles/:id" do
      it "rejects cross-bill modification when association belongs to another bill" do
        other_bna = create(:bill_news_article, bill: other_bill)

        patch "/admin/bills/#{bill.id}/news_articles/#{other_bna.id}",
          params: {approved: true},
          headers: {"Accept" => "application/json"}

        expect([404, 422]).to include(response.status)
        expect(other_bna.reload.approved).to be(false)
      end

      it "approves article, records admin, sets approved_at, and increments review_version" do
        expect(bill_news_article.approved).to be(false)
        expect(bill_news_article.review_version).to eq(0)

        patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
          params: {approved: true},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        reloaded = bill_news_article.reload
        expect(reloaded.approved).to be(true)
        expect(reloaded.approved_by_id).to eq(admin.id)
        expect(reloaded.approved_at).to be_present
        expect(reloaded.review_version).to eq(1)

        body = response.parsed_body
        expect(body["approved"]).to be(true)
        expect(body["review_version"]).to eq(1)
      end

      it "withdraws approval, records admin, and increments review_version" do
        bill_news_article.approve!(by: admin)
        expect(bill_news_article.review_version).to eq(1)

        patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
          params: {approved: false},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        reloaded = bill_news_article.reload
        expect(reloaded.approved).to be(false)
        expect(reloaded.review_version).to eq(2)
      end

      it "sets stance and increments stance_version" do
        patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
          params: {stance: "support"},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        reloaded = bill_news_article.reload
        expect(reloaded.stance).to eq("support")
        expect(reloaded.stance_by_id).to eq(admin.id)
        expect(reloaded.stance_version).to eq(1)
      end

      it "clears stance and increments stance_version" do
        bill_news_article.set_stance!("support", by: admin)
        expect(bill_news_article.stance_version).to eq(1)

        patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
          params: {stance: ""},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        reloaded = bill_news_article.reload
        expect(reloaded.stance).to be_nil
        expect(reloaded.stance_version).to eq(2)
      end

      it "updates article_kind on the underlying news_article" do
        expect(news_article.article_kind).to eq("reporting")

        patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
          params: {article_kind: "op_ed"},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        expect(news_article.reload.article_kind).to eq("op_ed")
      end

      it "adds manual text, creates immutable NewsArticleTextVersion, links current_text_version, and increments review_version" do
        patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
          params: {text: "Manual full text provided by admin."},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        reloaded = bill_news_article.reload
        expect(reloaded.current_text_version).to be_present
        expect(reloaded.current_text_version.origin).to eq("manual")
        expect(reloaded.current_text_version.actor_id).to eq(admin.id)
        expect(reloaded.current_text_version.text).to eq("Manual full text provided by admin.")
        expect(reloaded.current_text_version.digest).to eq(Digest::SHA256.hexdigest("Manual full text provided by admin."))
        expect(reloaded.review_version).to eq(1)

        body = response.parsed_body
        expect(body["has_text"]).to be(true)
        expect(body["text_origin"]).to eq("manual")
        expect(body["excerpt"]).to eq("Manual full text provided by admin.")
      end

      it "does not trigger summary generation when approving or adding manual text" do
        expect {
          patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
            params: {approved: true, text: "Some text"},
            headers: {"Accept" => "application/json"}
        }.not_to have_enqueued_job(GenerateBillSummaryJob)

        expect(BillSummaryRevision.where(bill: bill).count).to eq(0)
      end

      it "returns 422 for invalid parameters such as invalid stance" do
        patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
          params: {stance: "neutral"},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "handles JSON PATCH with empty bill_news_article without raising 400 ParameterMissing" do
        patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
          params: {bill_news_article: {}},
          headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
      end

      context "with Inertia requests" do
        let(:inertia_headers) do
          {
            "X-Inertia" => "true",
            "X-Inertia-Version" => InertiaRails.configuration.version.to_s
          }
        end

        it "toggles approval, redirects back with 303 See Other, and delivers updated news_articles on redirect" do
          expect(bill_news_article.approved).to be(false)

          patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
            params: {approved: true},
            headers: inertia_headers

          expect(response).to have_http_status(:see_other)
          expect(response).to redirect_to(summary_bill_creator_path(bill))

          follow_redirect!
          expect(response).to have_http_status(:ok)
          expect(inertia).to render_component(Pages::BILL_CREATOR)
          expect(bill_news_article.reload.approved).to be(true)
          expect(bill_news_article.review_version).to eq(1)

          articles = inertia.props[:news_articles]
          expect(articles).to be_an(Array)
          target = articles.find { |a| a[:id] == bill_news_article.id }
          expect(target[:approved]).to be(true)
          expect(target[:review_version]).to eq(1)
        end

        it "updates stance, redirects back with 303 See Other, and delivers updated stance on redirect" do
          patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
            params: {stance: "support"},
            headers: inertia_headers

          expect(response).to have_http_status(:see_other)
          expect(response).to redirect_to(summary_bill_creator_path(bill))

          follow_redirect!
          expect(response).to have_http_status(:ok)
          expect(inertia).to render_component(Pages::BILL_CREATOR)
          reloaded = bill_news_article.reload
          expect(reloaded.stance).to eq("support")
          expect(reloaded.stance_version).to eq(1)

          articles = inertia.props[:news_articles]
          target = articles.find { |a| a[:id] == bill_news_article.id }
          expect(target[:stance]).to eq("support")
          expect(target[:stance_version]).to eq(1)
        end

        it "updates article_kind, redirects back with 303 See Other, and delivers updated article_kind on redirect" do
          patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
            params: {article_kind: "op_ed"},
            headers: inertia_headers

          expect(response).to have_http_status(:see_other)
          expect(response).to redirect_to(summary_bill_creator_path(bill))

          follow_redirect!
          expect(response).to have_http_status(:ok)
          expect(inertia).to render_component(Pages::BILL_CREATOR)
          expect(news_article.reload.article_kind).to eq("op_ed")

          articles = inertia.props[:news_articles]
          target = articles.find { |a| a[:id] == bill_news_article.id }
          expect(target[:article_kind]).to eq("op_ed")
        end

        it "adds manual text, redirects back with 303 See Other, and delivers updated text properties on redirect" do
          patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
            params: {text: "Manual text supplied via Inertia review."},
            headers: inertia_headers

          expect(response).to have_http_status(:see_other)
          expect(response).to redirect_to(summary_bill_creator_path(bill))

          follow_redirect!
          expect(response).to have_http_status(:ok)
          expect(inertia).to render_component(Pages::BILL_CREATOR)
          reloaded = bill_news_article.reload
          expect(reloaded.current_text_version).to be_present
          expect(reloaded.current_text_version.origin).to eq("manual")

          articles = inertia.props[:news_articles]
          target = articles.find { |a| a[:id] == bill_news_article.id }
          expect(target[:has_text]).to be(true)
          expect(target[:text_origin]).to eq("manual")
          expect(target[:excerpt]).to eq("Manual text supplied via Inertia review.")
        end

        it "redirects back with 303 See Other and Inertia errors on invalid parameters" do
          patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
            params: {stance: "neutral"},
            headers: inertia_headers

          expect(response).to have_http_status(:see_other)
          expect(response).to redirect_to(summary_bill_creator_path(bill))

          follow_redirect!
          expect(response).to have_http_status(:ok)
          expect(inertia).to render_component(Pages::BILL_CREATOR)
          expect(inertia.props[:errors][:news_article]).to match(/invalid stance/i)
        end

        it "redirects to root with alert on RecordNotFound" do
          patch "/admin/bills/#{bill.id}/news_articles/999999",
            params: {approved: true},
            headers: inertia_headers

          expect(response).to redirect_to(root_path)
          expect(flash[:alert]).to eq("Not found")
        end

        it "tolerates empty nested bill_news_article payload without raising 400 ParameterMissing" do
          patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}?bill_creator_tab=summary&sway_locale_id=3&selected_stages=clean-testimony&download_missing_assets=0&bill_creator_sort=latest_action",
            params: {bill_news_article: {}},
            headers: inertia_headers

          expect(response).to have_http_status(:see_other)
          expect(response).to redirect_to(summary_bill_creator_path(bill, sway_locale_id: 3))
        end

        it "supports nested bill_news_article parameters" do
          patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
            params: {bill_news_article: {approved: true}},
            headers: inertia_headers

          expect(response).to have_http_status(:see_other)
          expect(bill_news_article.reload.approved).to be(true)
        end
      end

      # @lat: [[news-review#Review action protocol and format negotiation]]
      # @lat: [[news-article-evidence#Article identity and bill association]]
      # @lat: [[news-article-evidence#Immutable article text]]
      # @lat: [[news-article-evidence#Discovery request receipt]]
      # @lat: [[news-text#News text acquisition]]
      # @lat: [[lazy-inertia-props#Why the props became callables]]
      describe "format negotiation, partial reload lazy prop isolation, and cross-bill receipt scoping" do
        let!(:news_article) { create(:news_article, canonical_url: "https://thebanner.com/story-1") }
        let!(:bill_news_article) { create(:bill_news_article, bill: bill, news_article: news_article) }

        it "treats X-Inertia: true with Accept: application/json as an Inertia redirect rather than raw JSON" do
          patch "/admin/bills/#{bill.id}/news_articles/#{bill_news_article.id}",
            params: {approved: true, stance: "support"},
            headers: {
              "X-Inertia" => "true",
              "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
              "Accept" => "application/json"
            }

          expect(response).to have_http_status(:see_other)
          expect(response).to redirect_to(summary_bill_creator_path(bill))
          expect(bill_news_article.reload.approved).to be(true)
        end

        it "isolates SQL queries during partial reloads of news_articles vs summary_sources" do
          queries_for = lambda do |partial_data|
            queries = []
            sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
              sql = payload[:sql].to_s
              queries << sql if payload[:name] != "SCHEMA" && !payload[:cached] && sql.match?(/\A\s*SELECT\b/i)
            end
            begin
              get summary_bill_creator_path(bill), headers: {
                "X-Inertia" => "true",
                "X-Inertia-Version" => InertiaRails.configuration.version.to_s,
                "X-Inertia-Partial-Component" => Pages::BILL_CREATOR,
                "X-Inertia-Partial-Data" => partial_data
              }
            ensure
              ActiveSupport::Notifications.unsubscribe(sub)
            end
            queries
          end

          news_queries = queries_for.call("news_articles")
          expect(inertia.props.keys.map(&:to_s)).to include("news_articles")
          expect(inertia.props.keys.map(&:to_s)).not_to include("summary_sources")
          expect(news_queries.none? { |q| q.include?("FROM \"organizations\"") }).to be(true)

          source_queries = queries_for.call("summary_sources")
          expect(inertia.props.keys.map(&:to_s)).to include("summary_sources")
          expect(inertia.props.keys.map(&:to_s)).not_to include("news_articles")
          expect(source_queries.any? { |q| q.include?("bill_news_articles") }).to be(true)
        end

        it "returns 404 when discovery_request_id belongs to another admin or another bill" do
          other_admin = create(:user, :sway_admin)
          User.send(:remove_const, :ADMIN_PHONES)
          User.const_set(:ADMIN_PHONES, [admin.phone, other_admin.phone])
          other_admin_receipt = create(:news_article_discovery_request, bill: bill, requested_by: other_admin)
          other_bill_receipt = create(:news_article_discovery_request, bill: other_bill, requested_by: admin)

          post "/admin/bills/#{bill.id}/news_articles",
            params: {discovery_request_id: other_admin_receipt.id},
            headers: {"Accept" => "application/json"}
          expect(response).to have_http_status(:not_found)

          post "/admin/bills/#{bill.id}/news_articles",
            params: {discovery_request_id: other_bill_receipt.id},
            headers: {"Accept" => "application/json"}
          expect(response).to have_http_status(:not_found)
        end

        it "serializes AdminBillNewsArticleResource safely when canonical_url is malformed" do
          malformed_article = create(:news_article, canonical_url: "https://thebanner.com/valid-init")
          malformed_article.update_column(:canonical_url, "https://[invalid-ipv6-host/path")
          bna = create(:bill_news_article, bill: bill, news_article: malformed_article)

          serialized = JSON.parse(AdminBillNewsArticleResource.new(bna).serialize)
          expect(serialized["domain"]).to be_nil
        end
      end
    end
  end
end
