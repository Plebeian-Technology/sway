# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Bills admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :post,
    path: "/bills",
    params: {bill: {title: "T", kind: "local", sway_locale_id: 1}}
end

# The Bill Creator page itself. It replaced POST /bills/:id/prepare_prompt as
# the way the summary prompt reaches the browser, so the admin gate that
# covered that endpoint has to cover this one instead — the prompt is built
# here now, and nothing else guards it.
RSpec.describe "Bill Creator summary tab admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :get,
    path: "/admin/bill_creator/1/summary"
end

RSpec.describe "Bills testimony_letter_stance admin gate", type: :request do
  include_examples "requires sway admin",
    verb: :patch,
    path: "/bills/1/testimony_letter_stance",
    params: {position: 0, stance: "oppose"}
end

RSpec.describe "Bills LLM actions", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }

  let(:bill) do
    legislator = sway_locale.legislators.first
    create(:bill, sway_locale: sway_locale, legislator: legislator)
  end

  # @lat: [[bill-summary-call-preconditions#Why generate_bill_summary_job_spec.rb's default fixture sets bill.extracted_text, not just :with_diff_content]]
  let(:summarizable_bill) do
    legislator = sway_locale.legislators.first
    create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      external_id: "SUMMARIZABLE-1",
      extracted_text: "Section 1. The Mayor shall submit an annual report."
    )
  end

  describe "POST /bills/:id/generate_summary" do
    context "when the bill has source text to summarize (valid case)" do
      let(:bill) { summarizable_bill }
      let(:provisioning) do
        create(:bill_llm_provisioning, :with_diff_content, bill: bill)
      end

      before { provisioning }

      it "enqueues GenerateBillSummaryJob and redirects to edit" do
        expect { post generate_summary_bill_path(bill) }.to have_enqueued_job(
          GenerateBillSummaryJob
        ).with(bill.id)

        expect(response).to redirect_to(summary_bill_creator_path(bill))
      end

      it "transitions provisioning to pending" do
        post generate_summary_bill_path(bill)
        expect(provisioning.reload.generation_status).to eq("pending")
      end

      it "saves supplemental_testimony before enqueuing" do
        post generate_summary_bill_path(bill),
          params: {
            supplemental_testimony: "Admin testimony notes"
          }
        expect(provisioning.reload.supplemental_testimony).to eq(
          "Admin testimony notes"
        )
      end
    end

    # `generate_summary` behaves like `regenerate_summary` here: as it
    # enqueues, it wipes any leftover `summary_run_id` and `generation_error`.
    # Otherwise a late callback from an earlier failed run could look itself up
    # by `summary_run_id` and overwrite the row the new run just created.
    context "when a prior failed run left summary_run_id + generation_error set (REVIEW INFO #1)" do
      let(:bill) { summarizable_bill }
      let(:provisioning) do
        create(
          :bill_llm_provisioning,
          :failed,
          :with_diff_content,
          bill: bill,
          summary_run_id: "old-failed-run-uuid"
        )
      end

      before { provisioning }

      it "clears summary_run_id and generation_error and still enqueues + redirects" do
        expect(provisioning.summary_run_id).to eq("old-failed-run-uuid")
        expect(provisioning.generation_error).to be_present

        expect { post generate_summary_bill_path(bill) }.to have_enqueued_job(
          GenerateBillSummaryJob
        ).with(bill.id)

        provisioning.reload
        expect(provisioning.summary_run_id).to be_nil
        expect(provisioning.generation_error).to be_nil
        expect(provisioning.generation_status).to eq("pending")
        expect(response).to redirect_to(summary_bill_creator_path(bill))
      end
    end

    # The picker renders on the branches this endpoint serves too, so a model
    # picked there has to survive the round trip.
    # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
    context "when the operator picked a model for this run" do
      let(:bill) { summarizable_bill }
      let(:provisioning) do
        create(:bill_llm_provisioning, :with_diff_content, bill: bill)
      end

      before { provisioning }

      it "carries a supported model through to the job" do
        expect {
          post generate_summary_bill_path(bill), params: {summarization_model: "claude-opus-5-5"}
        }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summarization_model: "claude-opus-5-5")
      end

      it "carries an OpenRouter model choice through to the job without modifying standing settings" do
        expect {
          post generate_summary_bill_path(bill), params: {summarization_model: "Deepseek Pro Latest"}
        }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, summarization_model: "Deepseek Pro Latest")

        expect(AdminSetting.singleton.reload.summarization_model).not_to eq("Deepseek Pro Latest")
      end

      it "enqueues nothing and says so when the model is not one Sway offers" do
        expect {
          post generate_summary_bill_path(bill), params: {summarization_model: "gpt-9"}
        }.not_to have_enqueued_job(GenerateBillSummaryJob)

        follow_redirect!
        expect(response.body).to include("not one Sway offers")
      end

      it "leaves the standing AdminSetting default untouched" do
        expect {
          post generate_summary_bill_path(bill), params: {summarization_model: "claude-opus-5-5"}
        }.not_to change { AdminSetting.singleton.reload.summarization_model }
      end

      it "leaves the row alone when it refuses the model" do
        post generate_summary_bill_path(bill), params: {summarization_model: "gpt-9"}

        expect(provisioning.reload.generation_status).not_to eq("pending")
      end
    end

    context "when the operator supplied reasoning_effort" do
      let(:bill) { summarizable_bill }
      let(:provisioning) do
        create(:bill_llm_provisioning, :with_diff_content, bill: bill)
      end

      before { provisioning }

      it "carries a supported reasoning_effort through to the job" do
        AdminSetting.singleton.update!(summarization_model: "Opus Latest")

        expect {
          post generate_summary_bill_path(bill), params: {reasoning_effort: "high"}
        }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id, reasoning_effort: "high")
      end

      it "rejects unsupported reasoning_effort with an Inertia generation error" do
        expect {
          post generate_summary_bill_path(bill), params: {reasoning_effort: "ultra"}
        }.not_to have_enqueued_job(GenerateBillSummaryJob)

        expect(response).to redirect_to(summary_bill_creator_path(bill))
        expect(session.dig(:inertia_errors, :generation)).to eq(
          "That reasoning level is not supported. Choose default, low, medium, or high."
        )
        follow_redirect!
        expect(response.body).to include("That reasoning level is not supported. Choose default, low, medium, or high.")
      end

      it "rejects reasoning_effort for a non-reasoning per-run model with an Inertia generation error" do
        expect {
          post generate_summary_bill_path(bill),
            params: {reasoning_effort: "high", summarization_model: "claude-haiku-5-5"}
        }.not_to have_enqueued_job(GenerateBillSummaryJob)

        expect(response).to redirect_to(summary_bill_creator_path(bill))
        expect(session.dig(:inertia_errors, :generation)).to eq(
          "That reasoning level is not supported. Choose default, low, medium, or high."
        )
        follow_redirect!
        expect(response.body).to include("That reasoning level is not supported. Choose default, low, medium, or high.")
      end

      it "rejects reasoning_effort when standing model is non-reasoning with an Inertia generation error" do
        AdminSetting.singleton.update!(summarization_model: "claude-haiku-5-5")

        expect {
          post generate_summary_bill_path(bill), params: {reasoning_effort: "high"}
        }.not_to have_enqueued_job(GenerateBillSummaryJob)

        expect(response).to redirect_to(summary_bill_creator_path(bill))
        expect(session.dig(:inertia_errors, :generation)).to eq(
          "That reasoning level is not supported. Choose default, low, medium, or high."
        )
      end
    end

    context "when provisioning has no diff_content" do
      let(:provisioning) do
        create(:bill_llm_provisioning, bill: bill, diff_content: nil)
      end

      before { provisioning }

      it "redirects when no pipeline data" do
        post generate_summary_bill_path(bill)
        expect(response).to redirect_to(summary_bill_creator_path(bill))
      end

      it "does not enqueue a job" do
        expect {
          post generate_summary_bill_path(bill)
        }.not_to have_enqueued_job(GenerateBillSummaryJob)
      end
    end

    # @lat: [[bill-summary-call-preconditions#Why generate_bill_summary_job_spec.rb's default fixture sets bill.extracted_text, not just :with_diff_content]]
    context "when generation is already pending (idempotency)" do
      let(:bill) { summarizable_bill }
      let(:provisioning) do
        create(:bill_llm_provisioning, :pending, :with_diff_content, bill: bill)
      end

      before { provisioning }

      it "redirects without enqueuing" do
        post generate_summary_bill_path(bill)
        expect(response).to redirect_to(summary_bill_creator_path(bill))
      end

      it "does not enqueue another job" do
        expect {
          post generate_summary_bill_path(bill)
        }.not_to have_enqueued_job(GenerateBillSummaryJob)
      end
    end

    context "when generation is already generating (idempotency)" do
      let(:bill) { summarizable_bill }
      let(:provisioning) do
        create(
          :bill_llm_provisioning,
          :generating,
          :with_diff_content,
          bill: bill
        )
      end

      before { provisioning }

      it "redirects without enqueuing" do
        post generate_summary_bill_path(bill)
        expect(response).to redirect_to(summary_bill_creator_path(bill))
      end

      it "does not enqueue another job" do
        expect {
          post generate_summary_bill_path(bill)
        }.not_to have_enqueued_job(GenerateBillSummaryJob)
      end
    end

    describe "for a bearer request" do
      let(:bill) { summarizable_bill }
      let(:json_headers) { authenticate_as(user).merge("Accept" => "application/json") }

      # @lat: [[mobile-bill-creator#Sections#The summary generation section#Answering generate and regenerate in JSON]]
      it "queues the run and answers 200 with an empty body" do
        create(:bill_llm_provisioning, :with_diff_content, bill: bill)

        expect {
          post generate_summary_bill_path(bill), headers: json_headers
        }.to have_enqueued_job(GenerateBillSummaryJob).with(bill.id)

        expect(response).to have_http_status(:ok)
        expect(response.parsed_body).to eq({})
      end

      it "answers a run already in flight with 422 and the reason under generation" do
        create(:bill_llm_provisioning, :pending, :with_diff_content, bill: bill)

        expect {
          post generate_summary_bill_path(bill), headers: json_headers
        }.not_to have_enqueued_job(GenerateBillSummaryJob)

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body.dig("error", "code")).to eq("validation_failed")
        expect(response.parsed_body.dig("error", "details", "generation")).to eq("Generation already in progress")
      end

      it "still redirects a web refusal to the summary tab with the reason as an Inertia error" do
        create(:bill_llm_provisioning, :pending, :with_diff_content, bill: bill)

        post generate_summary_bill_path(bill)

        expect(response).to redirect_to(summary_bill_creator_path(bill))
        follow_redirect!
        expect(inertia).to render_component(Pages::BILL_CREATOR)
        expect(inertia.props[:errors][:generation]).to eq("Generation already in progress")
      end
    end
  end

  describe "GET /bills/:id/edit" do
    # @lat: [[bill-llm-provisioning-factory-design#Why the request spec asks the controller for the prop, not the fixture]]
    it "serves the bill_llm_provisioning row on the bill prop" do
      create(:bill_llm_provisioning, :completed, bill: bill)

      get pipeline_bill_creator_path(bill)

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)

      served = inertia.props[:bill].deep_symbolize_keys[:bill_llm_provisioning]
      expect(served).to be_present
      expect(served[:generation_status]).to eq("completed")
      expect(served[:llm_summary]).to eq("Test summary")
    end

    it "handles nil bill_llm_provisioning gracefully" do
      bill.reload
      expect(bill.bill_llm_provisioning).to be_nil
    end

    # The bill_artifact_mirrors prop is now built by
    # BillCreator::ResourceCachePanelSerializer. The prop name and the shape of
    # each row are unchanged from the old BillArtifactMirror#to_builder_hash;
    # only where the data comes from has changed.
    it "includes bill_artifact_mirrors Inertia prop on the pipeline_llm tab" do
      bill.create_bill_llm_provisioning!(
        llm_summary: "summary",
        llm_generated_at: 1.hour.ago
      )

      get pipeline_bill_creator_path(bill)
      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)

      mirrors = inertia.props[:bill_artifact_mirrors]
      expect(mirrors).to be_an(Array)
      expect(mirrors.length).to eq(1)
      first = mirrors.first
      key_set = first.keys.map(&:to_s)
      expect(key_set).to match_array(%w[tier last_generated_at version_id stale source_artifact_id])
      expect(first[:tier] || first["tier"]).to eq("summary")
    end

    # @lat: [[picker-bills-serializer-design#BillPickerRow.test.tsx notes]]
    it "ships enriched picker `bills` rows with sponsor + vote/active-position tallies" do
      create(:legislator_vote, bill: bill, legislator: bill.legislator)
      create(
        :organization_bill_position,
        bill: bill,
        organization: create(:organization, sway_locale: sway_locale, name: "Active Org")
      )
      create(
        :organization_bill_position,
        bill: bill,
        organization: create(:organization, sway_locale: sway_locale, name: "Inactive Org"),
        active: false
      )

      get creator_bill_creator_path(bill)
      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)

      bills_prop = inertia.props[:bills]
      expect(bills_prop).to be_present
      row = bills_prop.find { |b| (b[:id] || b["id"]) == bill.id }
      expect(row).to be_present
      expect(row[:sponsor_name] || row["sponsor_name"]).to eq(bill.legislator.full_name)
      expect(row[:status] || row["status"]).to eq(bill.status)
      expect(row[:chamber] || row["chamber"]).to eq(bill.chamber)
      expect(row[:category] || row["category"]).to eq(bill.category)
      expect(row[:introduced_date_time_utc] || row["introduced_date_time_utc"]).to be_present
      expect(row[:legislator_vote_count] || row["legislator_vote_count"]).to eq(1)
      # Only the ACTIVE org position is counted; the inactive one is excluded.
      expect(row[:organization_position_count] || row["organization_position_count"]).to eq(1)
    end

    # @lat: [[picker-bills-serializer-design#Why it skips Bill.to_builder]]
    it "issues a constant number of bill_interesting_scores queries regardless of bill count (no N+1 — SPEC Req 9)" do
      # @lat: [[steep-query-count-block-splat-workaround#Why the query-count subscriber block keeps its |*, payload| shape]]
      BillInterestingScoreCalculator.new(bill).call

      query_count_1 = 0
      subscriber_1 =
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          sql = payload[:sql].to_s.downcase
          query_count_1 += 1 if sql.include?("bill_interesting_scores")
        end
      get creator_bill_creator_path(bill)
      ActiveSupport::Notifications.unsubscribe(subscriber_1)
      # The subquery has to actually run. Without this check the example could
      # pass with zero queries in both measurements and prove nothing.
      expect(query_count_1).to be >= 1

      3.times do |i|
        extra_bill =
          create(
            :bill,
            sway_locale: sway_locale,
            legislator: bill.legislator,
            external_id: "n1-score-bill-#{i}",
            scheduled_release_date_utc: nil
          )
        BillInterestingScoreCalculator.new(extra_bill).call
      end

      query_count_n = 0
      subscriber_n =
        ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
          sql = payload[:sql].to_s.downcase
          query_count_n += 1 if sql.include?("bill_interesting_scores")
        end
      get creator_bill_creator_path(bill)
      ActiveSupport::Notifications.unsubscribe(subscriber_n)

      expect(query_count_n).to eq(query_count_1),
        "Expected constant bill_interesting_scores query count (got #{query_count_1} for 1 bill, #{query_count_n} for 4 bills) — N+1 detected"
    end

    # @lat: [[picker-bills-serializer-design#Why timeliness is recomputed live, not read from the stored row]]
    it "computes the live badge/timeliness at READ-TIME from stored dates, without a score recompute" do
      # Move introduced_date_time_utc well outside the 30-days-either-side
      # window so only house_vote_date_time_utc decides the checks below. The
      # factory's default of about a month ago sits too near the boundary to
      # isolate the effect being tested.
      bill.update_column(:introduced_date_time_utc, 100.days.ago)
      BillInterestingScoreCalculator.new(bill).call
      expect(BillInterestingScore.count).to eq(1)

      bill.update_column(:house_vote_date_time_utc, 20.days.ago)

      expect {
        get creator_bill_creator_path(bill)
      }.not_to change(BillInterestingScore, :count)
      expect(inertia).to render_component(Pages::BILL_CREATOR)

      row = inertia.props[:bills].find { |b| (b[:id] || b["id"]) == bill.id }
      expect(row).to be_present
      badges = row[:interesting_badges] || row["interesting_badges"]
      score = row[:interesting_score_normalized] || row["interesting_score_normalized"]
      expect(badges).to include("live")
      expect(score).to be > 0

      bill.update_column(:house_vote_date_time_utc, 40.days.ago)

      expect {
        get creator_bill_creator_path(bill)
      }.not_to change(BillInterestingScore, :count)

      row_after = inertia.props[:bills].find { |b| (b[:id] || b["id"]) == bill.id }
      badges_after = row_after[:interesting_badges] || row_after["interesting_badges"]
      expect(badges_after).not_to include("live")
    end

    # @lat: [[bills-controller-design#The web bills index grows a stable page window]]
    it "ships bill_artifact_mirrors regardless of tab_key (not gated by tab)" do
      bill.create_bill_llm_provisioning!(
        llm_summary: "summary",
        llm_generated_at: 1.hour.ago
      )
      # @lat: [[admin-hub-and-tabs#Each Bill Creator tab has its own path]]
      get creator_bill_creator_path(bill)
      expect(response).to have_http_status(:ok)

      mirrors = inertia.props[:bill_artifact_mirrors]
      expect(mirrors).to be_an(Array)
      expect(mirrors.length).to eq(1)
      expect(mirrors.first[:tier] || mirrors.first["tier"]).to eq("summary")
    end

    it "returns an empty bill_artifact_mirrors array when nothing has been generated yet (any tab)" do
      get pipeline_bill_creator_path(bill)
      expect(response).to have_http_status(:ok)
      expect(inertia.props[:bill_artifact_mirrors]).to eq([])
    end

    # A list of every bill fetched to disk. It goes out on every bill-edit
    # response, like bill_artifact_mirrors, and it belongs to the
    # PIPELINE_LLM_ONLY_PROPS group the WebSocket refreshes, so it updates
    # along with the rest of the panel.
    it "ships fetched_bills Inertia prop with on-disk inventory" do
      Dir.mktmpdir do |tmp|
        with_app_config(:legislation, legislation_bills_raw_root: tmp) do
          # @lat: [[testing-the-toolchain#An assertion that cannot fail proves nothing]]
          dir = Legislation::Paths.bill_artifact_dir(bill.external_id, sway_locale: bill.sway_locale.name)
          FileUtils.mkdir_p(dir)
          File.write(dir.join("bill.pdf"), "%PDF-1.4")
          File.write(dir.join("metadata.json"), "{}")

          get pipeline_bill_creator_path(bill)
          expect(response).to have_http_status(:ok)

          fetched = inertia.props[:fetched_bills]
          expect(fetched).to be_an(Array)
          expect(fetched.length).to eq(1)
          row = fetched.first
          expect(row[:external_id] || row["external_id"]).to eq(bill.external_id)
          expect(row[:bill_id] || row["bill_id"]).to eq(bill.id)
          expect(row[:pdf_present] || row["pdf_present"]).to be true
          expect(row[:bill_row_exists] || row["bill_row_exists"]).to be true
        end
      end
    end

    it "ships an empty fetched_bills array when bills_raw_root is empty" do
      Dir.mktmpdir do |tmp|
        with_app_config(:legislation, legislation_bills_raw_root: tmp) do
          get pipeline_bill_creator_path(bill)
          expect(response).to have_http_status(:ok)
          expect(inertia.props[:fetched_bills]).to eq([])
        end
      end
    end
  end

  # @lat: [[bill-summary-prompt-prop-delivery#Why it lives at the top level, not inside bill]]
  # @lat: [[inertia-reload-only-helper-version-header-gap#Why some partial-reload specs build the request by hand]]
  # @lat: [[bill-pipeline-refresh-active-statuses-drift#Why the "Pipeline failed" alert needed its own prop]]
  describe "the bill_pipeline_last_failure prop" do
    it "carries the reason the last run failed" do
      create(:legislation_pipeline_run, bill: bill, status: "failed",
        error_message: "fetch_hearings: matter 9928 not found")

      get summary_bill_creator_path(bill)

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:bill][:bill_pipeline_last_failure][:error_message])
        .to eq("fetch_hearings: matter 9928 not found")
    end

    # @lat: [[bill-pipeline-refresh-active-statuses-drift#Why the "Pipeline failed" alert needed its own prop#Why the alert's remedy needs the failed run's own id]]
    it "carries the failed run's own id, so the alert can link to that run" do
      run = create(:legislation_pipeline_run, bill: bill, status: "failed",
        error_message: "fetch_hearings: matter 9928 not found")

      get summary_bill_creator_path(bill)

      expect(inertia.props[:bill][:bill_pipeline_last_failure][:run_id]).to eq(run.id)
    end

    it "is nil when no run has failed" do
      create(:legislation_pipeline_run, bill: bill, status: "queued")

      get summary_bill_creator_path(bill)

      expect(inertia.props[:bill][:bill_pipeline_last_failure]).to be_nil
    end

    # The newest failure, not the first one found — an operator looking at this
    # needs the run they just watched fail.
    it "reports the most recent failure when there have been several" do
      create(:legislation_pipeline_run, bill: bill, status: "failed",
        error_message: "the older failure", created_at: 2.days.ago)
      create(:legislation_pipeline_run, bill: bill, status: "failed",
        error_message: "the newer failure", created_at: 1.hour.ago)

      get summary_bill_creator_path(bill)

      expect(inertia.props[:bill][:bill_pipeline_last_failure][:error_message]).to eq("the newer failure")
    end
  end

  # @lat: [[bill-creator-summary-tab#Choosing the model for one regeneration]]
  describe "the per-run model picker props" do
    it "serves every model AdminSetting offers, with its short label" do
      get summary_bill_creator_path(bill)

      expect(inertia.props[:summary_model_options].pluck(:id))
        .to eq(AdminSetting.offered_models)
      expect(inertia.props[:summary_model_options].pluck(:label))
        .to eq([
          "Haiku 5.5",
          "Sonnet 5.5",
          "Opus 5.5",
          "Opus Latest",
          "Sonnet Latest",
          "Haiku Latest",
          "Gemini Argon Latest",
          "Gemini Flash Latest",
          "GLM Latest",
          "Deepseek Pro Latest",
          "Deepseek Flash Latest",
          "OpenRouter Auto"
        ])

      argon = inertia.props[:summary_model_options].find { |opt| opt[:id] == "Gemini Argon Latest" }
      expect(argon[:supports_reasoning]).to be(true)

      haiku = inertia.props[:summary_model_options].find { |opt| opt[:id] == "claude-haiku-5-5" }
      expect(haiku[:supports_reasoning]).to be(false)
    end

    it "reflects dynamically added offered models in summary_model_options" do
      allow(Llm::OpenRouterModelsService).to receive(:lookup).with("openai/gpt-4o", any_args).and_return({
        id: "openai/gpt-4o",
        label: "OpenAI: GPT-4o",
        supports_reasoning: false
      })
      allow(Llm::OpenRouterModelsService).to receive(:call).and_return([
        {id: "openai/gpt-4o", label: "OpenAI: GPT-4o", supports_reasoning: false}
      ])

      AdminSetting.singleton.add_offered_model!("openai/gpt-4o")

      get summary_bill_creator_path(bill)

      options = inertia.props.fetch(:summary_model_options)
      expect(options.pluck(:id)).to include("openai/gpt-4o")
      expect(options.find { |opt| opt[:id] == "openai/gpt-4o" }[:label]).to eq("OpenAI: GPT-4o")
    end

    it "reflects dynamically removed offered models in summary_model_options" do
      AdminSetting.singleton.remove_offered_model!("OpenRouter Auto")

      get summary_bill_creator_path(bill)

      options = inertia.props.fetch(:summary_model_options)
      expect(options.pluck(:id)).not_to include("OpenRouter Auto")
    end

    it "names the standing default so the picker starts on it" do
      AdminSetting.singleton.update!(
        summarization_model: "Opus Latest",
        summarization_reasoning_effort: "high"
      )

      get summary_bill_creator_path(bill)

      expect(inertia.props[:current_summarization_model]).to eq("Opus Latest")
      expect(inertia.props[:current_summarization_reasoning_effort]).to eq("high")
    end
  end

  describe "the summary_prompt prop" do
    it "is left out of an ordinary visit" do
      bill.create_bill_llm_provisioning!(diff_content: "diff sample")

      get summary_bill_creator_path(bill)

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props).not_to have_key(:summary_prompt)
    end

    it "is served at the top level when the browser asks for it by name" do
      bill.create_bill_llm_provisioning!(diff_content: "diff sample")

      get summary_bill_creator_path(bill), headers: {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version,
        "X-Inertia-Partial-Component" => Pages::BILL_CREATOR,
        "X-Inertia-Partial-Data" => "summary_prompt"
      }

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      prompt = inertia.props[:summary_prompt]
      expect(prompt).to be_a(String)
      expect(prompt).to include(bill.external_id)
      # The prompt asks for `summary_markdown`, the field name used in
      # config/schemas/bill_summary.json. The older `llm_summary` wording no
      # longer appears in the prompt.
      expect(prompt).to include("summary_markdown")
    end

    it "is not nested inside the bill prop" do
      get summary_bill_creator_path(bill), headers: {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version,
        "X-Inertia-Partial-Component" => Pages::BILL_CREATOR,
        "X-Inertia-Partial-Data" => "summary_prompt,bill"
      }

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:summary_prompt]).to be_a(String)
      expect(inertia.props[:bill]).not_to have_key(:summary_prompt)
    end

    # The reason the prop had to move. This tab refreshes these three props
    # every 5 seconds. A prompt nested inside `bill` was thrown away with it;
    # a top-level prop nobody asked for is simply not sent, so the copy already
    # on screen survives the tick.
    it "is left out of the reload that refreshes the rest of the tab" do
      get summary_bill_creator_path(bill), headers: {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version,
        "X-Inertia-Partial-Component" => Pages::BILL_CREATOR,
        "X-Inertia-Partial-Data" => "bill,organizations,legislation_pipeline_run"
      }

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props).to include(:bill, :organizations)
      expect(inertia.props).not_to have_key(:summary_prompt)
    end

    # @lat: [[bill-summary-prompt-prop-delivery#Why JSON callers get it only on request]]
    it "is withheld from JSON callers that do not ask for it" do
      bill.create_bill_llm_provisioning!(diff_content: "diff sample")

      get summary_bill_creator_path(bill), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)).not_to have_key("summary_prompt")
    end

    it "produces a prompt even when no diff_content has been ingested" do
      get summary_bill_creator_path(bill), headers: {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version,
        "X-Inertia-Partial-Component" => Pages::BILL_CREATOR,
        "X-Inertia-Partial-Data" => "summary_prompt"
      }

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props[:summary_prompt]).to include("fetch the bill text")
    end
  end

  describe "the testimony_campaign_letters prop" do
    let(:campaign_letter_first_body) { "First letter body, sent by many people." }
    let(:campaign_letter_second_body) { "Second letter body, sent by many people." }
    let(:campaign_letters_artifact_text) { campaign_letter_first_body + campaign_letter_second_body }

    let(:campaign_letters_artifact) do
      {
        "version" => 1,
        "text" => campaign_letters_artifact_text,
        "counts" => {"raw_chars" => campaign_letters_artifact_text.length, "cleaned_chars" => campaign_letters_artifact_text.length},
        "letters" => [
          {"position" => 0, "character_offset" => 0, "characters" => campaign_letter_first_body.length,
           "sender_address" => "alice@everyactioncustom.com", "sender_domain" => "everyactioncustom.com",
           "source_kind" => "person_speaking_for_self", "source_evidence" => nil},
          {"position" => 1, "character_offset" => campaign_letter_first_body.length, "characters" => campaign_letter_second_body.length,
           "sender_address" => "bob@everyactioncustom.com", "sender_domain" => "everyactioncustom.com",
           "source_kind" => "person_speaking_for_self", "source_evidence" => nil}
        ],
        "campaign_drafts" => [
          {"id" => "campaigngroup0001", "letter_positions" => [0, 1], "campaign_origin" => true,
           "sender_count" => 2, "letter_count" => 2, "repeat_letter_count" => 0,
           "added_words" => "", "senders_added_words_left_out" => 0,
           "dominant_domain" => "everyactioncustom.com"}
        ]
      }
    end

    let!(:campaign_letters_provisioning) do
      create(:bill_llm_provisioning, bill: bill,
        extracted_testimony: "Testimony submitted at the hearing on this bill.",
        cleaned_testimony: campaign_letters_artifact,
        cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago)
    end

    let(:pipeline_tab_poll) do
      "bill,legislation_pipeline_run,active_legislation_pipeline_run,recent_pipeline_runs," \
        "bill_artifact_mirrors,fetched_bills,stale_pipeline_run_count,orphan_pipeline_run_count," \
        "testimony_coverage,testimony_campaign_drafts,testimony_claimed_affiliations," \
        "sending_service_domains,sending_service_domains_total"
    end

    let(:summary_tab_poll) do
      "bill,organizations,active_legislation_pipeline_run,testimony_coverage," \
        "testimony_campaign_drafts,testimony_claimed_affiliations,campaigns,summary_sources"
    end

    let(:bill_creator_partial_headers) do
      {
        "X-Inertia" => "true",
        "X-Inertia-Version" => InertiaRails.configuration.version,
        "X-Inertia-Partial-Component" => Pages::BILL_CREATOR
      }
    end

    it "is left out of an ordinary visit" do
      get summary_bill_creator_path(bill)

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      expect(inertia.props).not_to have_key(:testimony_campaign_letters)
    end

    it "is served at the top level as one bundle per draft when the browser asks for it by name" do
      get summary_bill_creator_path(bill),
        headers: bill_creator_partial_headers.merge("X-Inertia-Partial-Data" => "testimony_campaign_letters")

      expect(response).to have_http_status(:ok)
      expect(inertia).to render_component(Pages::BILL_CREATOR)
      bundles = inertia.props[:testimony_campaign_letters]
      expect(bundles).to be_an(Array)
      expect(bundles.length).to eq(1)
      expect(bundles.first.keys).to match_array(%w[content_hash letters])
      expect(bundles.first["content_hash"]).to eq("campaigngroup0001")
      expect(bundles.first["letters"].pluck("text")).to eq([campaign_letter_first_body, campaign_letter_second_body])
    end

    it "is left out of the Pipeline tab's five-second poll" do
      get summary_bill_creator_path(bill),
        headers: bill_creator_partial_headers.merge("X-Inertia-Partial-Data" => pipeline_tab_poll)

      expect(response).to have_http_status(:ok)
      expect(inertia.props).to include(:testimony_campaign_drafts)
      expect(inertia.props).not_to have_key(:testimony_campaign_letters)
    end

    it "is left out of the Summary tab's five-second poll, which still carries the drafts" do
      get summary_bill_creator_path(bill),
        headers: bill_creator_partial_headers.merge("X-Inertia-Partial-Data" => summary_tab_poll)

      expect(response).to have_http_status(:ok)
      expect(inertia.props).to include(:testimony_campaign_drafts)
      expect(inertia.props).not_to have_key(:testimony_campaign_letters)
    end

    it "is withheld from JSON callers that do not ask for it" do
      get summary_bill_creator_path(bill), as: :json

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/json")
      expect(JSON.parse(response.body)).not_to have_key("testimony_campaign_letters")
    end
  end

  describe "POST /bills/:id/approve_org_position" do
    it "creates Organization and OrganizationBillPosition" do
      expect {
        post approve_org_position_bill_path(bill),
          params: {
            org_name: "Baltimore Teachers Union",
            support: "FOR",
            summary: "Supports better schools"
          }
      }.to change(Organization, :count).by(1).and change(
        OrganizationBillPosition,
        :count
      ).by(1)

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      org = Organization.last
      expect(org.name).to eq("Baltimore Teachers Union")
      expect(OrganizationBillPosition.last.support).to eq("FOR")
    end

    # The frontend posts a stance as "support", "oppose" or "neutral". The
    # controller translates those into the stored values "FOR", "AGAINST" and
    # "ABSTAIN", so the column speaks one vocabulary across both newly
    # approved drafts and older rows.
    it "maps wire-side stance 'support' to storage enum 'FOR'" do
      post approve_org_position_bill_path(bill),
        params: {
          org_name: "Baltimore Teachers Union",
          support: "support",
          summary: "Supports better schools"
        }
      expect(OrganizationBillPosition.last.support).to eq("FOR")
    end

    it "maps wire-side stance 'oppose' to storage enum 'AGAINST'" do
      post approve_org_position_bill_path(bill),
        params: {org_name: "ACLU", support: "oppose", summary: "Opposes"}
      expect(OrganizationBillPosition.last.support).to eq("AGAINST")
    end

    it "maps wire-side stance 'neutral' to storage enum 'ABSTAIN'" do
      post approve_org_position_bill_path(bill),
        params: {org_name: "League of Women Voters", support: "neutral", summary: "Neutral"}
      expect(OrganizationBillPosition.last.support).to eq("ABSTAIN")
    end

    # A blank org_name stops early with a readable Inertia error, instead of
    # falling through to an unhandled validation error raised by
    # Organization#create!.
    it "rejects blank org_name with an inertia error" do
      expect {
        post approve_org_position_bill_path(bill),
          params: {org_name: "  ", support: "support", summary: "x"}
      }.not_to change(OrganizationBillPosition, :count)
      expect(response).to redirect_to(positions_bill_creator_path(bill))
    end

    # @lat: [[organization-position-removal#A refusal reaches the operator as a message, not a 500]]
    it "rejects blank summary with an inertia error instead of a 500" do
      expect {
        post approve_org_position_bill_path(bill),
          params: {org_name: "ACLU", support: "support", summary: "   "}
      }.not_to change(OrganizationBillPosition, :count)
      expect(response).to redirect_to(positions_bill_creator_path(bill))
    end

    it "rejects unknown stance with an inertia error" do
      expect {
        post approve_org_position_bill_path(bill),
          params: {org_name: "ACLU", support: "garbage", summary: "x"}
      }.not_to change(OrganizationBillPosition, :count)
    end

    # Clicking Approve a second time for the same bill and organization must
    # update the existing row's stance and summary. It must not quietly do
    # nothing by taking the "find" half of find_or_create_by!.
    it "amends stance + summary on a second approve" do
      post approve_org_position_bill_path(bill),
        params: {org_name: "ACLU", support: "support", summary: "v1"}
      expect(OrganizationBillPosition.last.support).to eq("FOR")
      expect(OrganizationBillPosition.last.summary).to eq("v1")

      expect {
        post approve_org_position_bill_path(bill),
          params: {org_name: "ACLU", support: "oppose", summary: "v2"}
      }.not_to change(OrganizationBillPosition, :count)
      expect(OrganizationBillPosition.last.support).to eq("AGAINST")
      expect(OrganizationBillPosition.last.summary).to eq("v2")
    end

    it "keeps no testimony for a neutral position, and approves one that carries none" do
      post approve_org_position_bill_path(bill),
        params: {org_name: "ACLU", support: "neutral", summary: "An argument nobody asked for."}

      stored = OrganizationBillPosition.last
      expect(stored.support).to eq("ABSTAIN")
      expect(stored.summary).to eq(OrganizationBillPosition::DEFAULT_SUMMARY)

      expect {
        post approve_org_position_bill_path(bill),
          params: {org_name: "Sierra Club", support: "neutral", summary: "   "}
      }.to change(OrganizationBillPosition, :count).by(1)
      expect(OrganizationBillPosition.last.support).to eq("ABSTAIN")
    end

    it "reuses existing organization with similar name (fuzzy match)" do
      existing =
        create(
          :organization,
          name: "Baltimore Teachers Union",
          sway_locale: sway_locale
        )

      expect {
        post approve_org_position_bill_path(bill),
          params: {
            org_name: "Baltimore Teachers Union",
            support: "FOR",
            summary: "Supports"
          }
      }.not_to change(Organization, :count)

      expect(OrganizationBillPosition.last.organization).to eq(existing)
    end

    # @lat: [[org-position-approval-guard-chain#Why approval used to leave a stale draft and no audit entry (UAT Test 5)]]
    context "draft-list cleanup + audit log (UAT Test 5)" do
      let!(:provisioning) do
        # :with_testimony — approval requires the bill to still hold the
        # evidence its drafts were drawn from. These examples are about
        # clearing the draft list and writing the audit entry, not about that
        # requirement, which has its own context below.
        create(
          :bill_llm_provisioning,
          :with_testimony,
          bill: bill,
          draft_org_positions: [
            {"org_name" => "ACLU", "stance" => "support", "summary" => "Supports"},
            {"org_name" => "Heritage", "stance" => "oppose", "summary" => "Opposes"}
          ]
        )
      end

      it "removes the matching draft entry from draft_org_positions when :index is provided" do
        post approve_org_position_bill_path(bill),
          params: {org_name: "ACLU", support: "support", summary: "Supports", index: 0, draft_org_name: "ACLU"}

        provisioning.reload
        expect(provisioning.draft_org_positions.length).to eq(1)
        expect(provisioning.draft_org_positions.first["org_name"]).to eq("Heritage")
      end

      it "leaves draft_org_positions untouched when :index is omitted (backwards-compat)" do
        post approve_org_position_bill_path(bill),
          params: {org_name: "ACLU", support: "support", summary: "Supports"}

        provisioning.reload
        expect(provisioning.draft_org_positions.length).to eq(2)
      end

      it "leaves draft_org_positions untouched when :index is out of bounds" do
        post approve_org_position_bill_path(bill),
          params: {org_name: "ACLU", support: "support", summary: "Supports", index: 99, draft_org_name: "ACLU"}

        provisioning.reload
        expect(provisioning.draft_org_positions.length).to eq(2)
      end

      it "emits an org_position_decision :approved activity log entry with the org name" do
        expect {
          post approve_org_position_bill_path(bill),
            params: {org_name: "ACLU", support: "support", summary: "Supports", index: 0, draft_org_name: "ACLU"}
        }.to change(PipelineActivityLogEntry.where(event_type: "org_position_decision"), :count).by(1)

        entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").order(:id).last
        expect(entry.payload["decision"]).to eq("approved")
        expect(entry.payload["org_name"]).to eq("ACLU")
        expect(entry.payload["bill_id"]).to eq(bill.id)
      end

      it "emits the audit entry even without a draft list (e.g. no provisioning row)" do
        provisioning.destroy
        bill.reload

        expect {
          post approve_org_position_bill_path(bill),
            params: {org_name: "ACLU", support: "support", summary: "Supports"}
        }.to change(PipelineActivityLogEntry.where(event_type: "org_position_decision"), :count).by(1)
      end

      # The approve notice follows the same shape as the reject and edit ones
      # ("Approved <Org> on <bill>."), so all three draft decisions confirm
      # themselves the same way and name what happened. The frontend used to
      # pop a generic toast instead.
      it "sets flash[:notice] naming the org and bill external_id" do
        post approve_org_position_bill_path(bill),
          params: {org_name: "ACLU", support: "support", summary: "Supports", index: 0, draft_org_name: "ACLU"}
        expect(flash[:notice]).to eq("Approved ACLU on #{bill.external_id}.")
      end
    end

    # @lat: [[organization-position-removal#A refusal reaches the operator as a message, not a 500]]
    context "evidence-retracted draft (B4-CR-02)" do
      let!(:provisioning) do
        create(
          :bill_llm_provisioning,
          bill: bill,
          draft_org_positions: [
            {"org_name" => "ACLU", "stance" => "support", "summary" => "Supports",
             BillLlmProvisioning::DRAFT_EVIDENCE_RETRACTED_KEY => "2026-07-01T00:00:00Z"}
          ]
        )
      end

      it "creates no public position and explains why" do
        expect {
          post approve_org_position_bill_path(bill),
            params: {org_name: "ACLU", support: "support", summary: "Supports", index: 0, draft_org_name: "ACLU"}
        }.not_to change(OrganizationBillPosition, :count)

        expect(response).to redirect_to(positions_bill_creator_path(bill))
        expect(provisioning.reload.draft_org_positions.length).to eq(1)
        follow_redirect!
        expect(inertia.props[:errors][:org_position]).to match(/testimony/i)
      end
    end

    context "the private-individual guard's operator override" do
      let!(:provisioning) do
        text = "From: resident@gmail.com\nI support this bill.\n\nAlex Example\n100 Example Street\nBaltimore, MD 21201\n"
        create(
          :bill_llm_provisioning,
          bill: bill,
          extracted_testimony: "Testimony submitted at the hearing on this bill.",
          cleaned_testimony: {
            "version" => 1, "text" => text, "counts" => {},
            "letters" => [
              {"position" => 0, "character_offset" => 0, "characters" => text.length,
               "sender_address" => "resident@gmail.com", "sender_domain" => "gmail.com",
               "source_kind" => "person_speaking_for_self", "source_evidence" => nil}
            ]
          },
          cleaned_testimony_at: 1.hour.ago, testimony_fetched_at: 2.hours.ago,
          draft_org_positions: [{"org_name" => "Alex Example", "stance" => "support", "summary" => "Supports the bill."}]
        )
      end

      it "refuses without the override flag, flagging the refusal for the frontend to offer one" do
        expect {
          post approve_org_position_bill_path(bill),
            params: {org_name: "Alex Example", support: "support", summary: "Supports the bill.",
                     index: 0, draft_org_name: "Alex Example"}
        }.not_to change(OrganizationBillPosition, :count)

        follow_redirect!
        expect(inertia.props[:errors][:org_position]).to match(/person writing for/i)
        expect(inertia.props[:errors][:private_individual_refusal]).to eq(true)
      end

      it "approves once the operator sends the confirmed override flag, and logs it" do
        expect {
          post approve_org_position_bill_path(bill),
            params: {
              org_name: "Alex Example", support: "support", summary: "Supports the bill.",
              index: 0, draft_org_name: "Alex Example", override_private_individual: true
            }
        }.to change(OrganizationBillPosition, :count).by(1)

        expect(flash[:notice]).to eq("Approved Alex Example on #{bill.external_id}.")
        entry = PipelineActivityLogEntry.where(event_type: "org_position_decision").order(:id).last
        expect(entry.payload["private_individual_override"]).to eq(true)
      end
    end

    # @lat: [[supplemental-testimony-write-rule#Why the request specs cover all three routes to attrs(clear: true)]]
    context "testimony cleared out from under existing drafts (A2-CR-01 / C2-CR-01)" do
      let!(:provisioning) do
        create(
          :bill_llm_provisioning,
          :with_diff_content,
          bill: bill,
          generation_status: "completed",
          supplemental_testimony: "Testimony of the ACLU, submitted at the hearing.",
          draft_org_positions: [
            {"org_name" => "ACLU", "stance" => "support", "summary" => "Supports"}
          ]
        )
      end

      # Route 1 — the Clear button (UpdateSupplementalTestimonyService).
      it "refuses approval after PATCH supplemental_testimony clears the paste" do
        patch supplemental_testimony_bill_path(bill), params: {clear_supplemental_testimony: true}
        expect(provisioning.reload.testimony_present?).to be(false)

        expect {
          post approve_org_position_bill_path(bill), params: {org_name: "ACLU", support: "support", summary: "Supports", index: 0, draft_org_name: "ACLU"}
        }.not_to change(OrganizationBillPosition, :count)

        expect(provisioning.reload.draft_org_positions.length).to eq(1)
        follow_redirect!
        expect(inertia.props[:errors][:org_position]).to match(/testimony/i)
      end

      # Route 2 — generate_summary passes the same clear flag through the same
      # #supplemental_testimony_args in bills_controller.rb.
      it "refuses approval after generate_summary clears the paste" do
        post generate_summary_bill_path(bill), params: {clear_supplemental_testimony: true}
        expect(provisioning.reload.testimony_present?).to be(false)

        expect {
          post approve_org_position_bill_path(bill), params: {org_name: "ACLU", support: "support", summary: "Supports", index: 0, draft_org_name: "ACLU"}
        }.not_to change(OrganizationBillPosition, :count)
        expect(provisioning.reload.draft_org_positions.length).to eq(1)
      end

      # Route 3 — regenerate_summary, the same again. The job's testimony check
      # deliberately has no `else` branch, so the run that follows without
      # testimony KEEPS these drafts instead of removing them. That is exactly
      # why the approval side has to refuse them.
      it "refuses approval after regenerate_summary clears the paste" do
        post regenerate_summary_bill_path(bill), params: {clear_supplemental_testimony: true}
        expect(provisioning.reload.testimony_present?).to be(false)

        expect {
          post approve_org_position_bill_path(bill), params: {org_name: "ACLU", support: "support", summary: "Supports", index: 0, draft_org_name: "ACLU"}
        }.not_to change(OrganizationBillPosition, :count)
        expect(provisioning.reload.draft_org_positions.length).to eq(1)
      end

      it "still approves while the paste is intact" do
        expect {
          post approve_org_position_bill_path(bill), params: {org_name: "ACLU", support: "support", summary: "Supports", index: 0, draft_org_name: "ACLU"}
        }.to change(OrganizationBillPosition, :count).by(1)
      end
    end

    context "news-sourced draft positions" do
      let(:news_article) { create(:news_article, article_kind: "reporting") }
      let(:bna) do
        b = create(
          :bill_news_article,
          bill: bill,
          news_article: news_article,
          approved: true,
          approved_by: user,
          approved_at: Time.current
        )
        b.update_columns(current_text_version_id: text_version.id)
        b
      end
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
          "speaker_role" => "Executive Director"
        }
      end
      let!(:provisioning) do
        create(
          :bill_llm_provisioning,
          bill: bill,
          draft_org_positions: [news_draft]
        )
      end

      it "approves a news draft without hearing testimony and sets ai_summary to nil" do
        expect {
          post approve_org_position_bill_path(bill),
            params: {
              org_name: "Baltimore Tenants Union",
              support: "support",
              summary: "Supports fair housing legislation for tenants.",
              index: 0,
              draft_org_name: "Baltimore Tenants Union"
            }
        }.to change(OrganizationBillPosition, :count).by(1)

        expect(response).to redirect_to(positions_bill_creator_path(bill))
        expect(flash[:notice]).to eq("Approved Baltimore Tenants Union on #{bill.external_id}.")
        position = OrganizationBillPosition.last
        expect(position&.support).to eq("FOR")
        expect(position&.ai_summary).to be_nil
        expect(provisioning.reload.draft_org_positions).to eq([])
      end

      it "refuses approval when matched organization has user memberships" do
        org = create(:organization, name: "Baltimore Tenants Union", sway_locale: bill.sway_locale)
        create(:user_organization_membership, organization: org, user: user)

        expect {
          post approve_org_position_bill_path(bill),
            params: {
              org_name: "Baltimore Tenants Union",
              support: "support",
              summary: "Supports fair housing legislation for tenants.",
              index: 0,
              draft_org_name: "Baltimore Tenants Union"
            }
        }.not_to change(OrganizationBillPosition, :count)

        expect(response).to redirect_to(positions_bill_creator_path(bill))
        follow_redirect!
        expect(inertia.props[:errors][:org_position]).to eq(
          "This organization has registered user accounts on Sway and manages its own positions — positions cannot be published on its behalf."
        )
      end

      it "refuses approval with an inertia error when news evidence is retracted" do
        bna.update_columns(approved: false)

        expect {
          post approve_org_position_bill_path(bill),
            params: {
              org_name: "Baltimore Tenants Union",
              support: "support",
              summary: "Supports fair housing legislation for tenants.",
              index: 0,
              draft_org_name: "Baltimore Tenants Union"
            }
        }.not_to change(OrganizationBillPosition, :count)

        expect(response).to redirect_to(positions_bill_creator_path(bill))
        follow_redirect!
        expect(inertia.props[:errors][:org_position]).to match(/retracted/i)
      end
    end
  end

  # The old POST /bills/:id/reject_org_position endpoint is gone. The frontend
  # now sends PATCH /bill_draft_org_positions/:id, which writes an
  # org_position_decision audit entry.
  describe "POST /bills/:id/reject_org_position" do
    it "returns 404 — the legacy endpoint is gone" do
      # Both the route and the action were deleted, so Rails answers through
      # its public error handling instead of raising. Check the HTTP response
      # and accept any 4xx: the router returns 404 today, while anyone who
      # brought the action back would show up as a 302 redirect or a 200.
      raised_class = nil
      response_status = nil
      begin
        post "/bills/#{bill.id}/reject_org_position", params: {org_name: "ACLU"}
        response_status = response.status
      rescue ActionController::RoutingError, ActionController::UrlGenerationError => e
        raised_class = e.class
      end
      endpoint_gone = !raised_class.nil? || (response_status && (400..499).cover?(response_status))
      expect(endpoint_gone).to be(true),
        "expected reject_org_position to be routed as 4xx or raise a routing error; got status=#{response_status.inspect}, raised=#{raised_class.inspect}"
    end
  end

  # @lat: [[bill-save-return-tab-routing#Why a bill save carries its own return tab]]
  describe "PATCH /bills/:id — where a save sends the operator" do
    it "returns the operator to the summary tab when the save came from it" do
      patch bill_path(bill), params: {summary: "An edited public summary.", return_tab: "summary", news_usage: "none"}

      expect(response).to redirect_to(summary_bill_creator_path(bill.id))
      expect(bill.reload.summary).to eq("An edited public summary.")
    end

    # The bill form sends no return_tab, and its own system spec reads the
    # legislator-votes anchor as the mark of a successful save. Unchanged.
    it "still returns to the creator tab when the save named no tab" do
      patch bill_path(bill), params: {summary: "An edited public summary.", news_usage: "none"}

      expect(response).to redirect_to(
        creator_bill_creator_path(bill.id, {event_key: "legislator_votes"})
      )
    end

    # The value steers a redirect, so it is matched against a fixed list rather
    # than interpolated. Anything unrecognised falls back to the default.
    it "ignores a tab it does not recognise rather than following it" do
      patch bill_path(bill), params: {summary: "An edited public summary.", return_tab: "https://example.com/", news_usage: "none"}

      expect(response).to redirect_to(
        creator_bill_creator_path(bill.id, {event_key: "legislator_votes"})
      )
    end

    # @lat: [[bills-controller-design#The create, update, and destroy actions]]
    it "says nothing of its own when the summary tab already reports the save" do
      patch bill_path(bill), params: {summary: "An edited public summary.", return_tab: "summary", news_usage: "none"}

      expect(flash[:notice]).to be_nil
      expect(bill.reload.summary).to eq("An edited public summary.")
    end

    # The other side of the wire: the bill form has no toast of its own, so the
    # flash is the only thing that tells the operator the save landed.
    it "still says Bill Updated when the save came from the bill form" do
      patch bill_path(bill), params: {summary: "An edited public summary.", news_usage: "none"}

      expect(flash[:notice]).to eq("Bill Updated")
    end

    # A refused save has to land on the same tab it came from too: the Summary
    # tab keeps no other copy of the operator's unsaved text, so a failure
    # that redirects anywhere else discards it.
    it "returns to the summary tab when a save from it is refused" do
      patch bill_path(bill), params: {summary: "", return_tab: "summary"}

      expect(response).to redirect_to(summary_bill_creator_path(bill.id))
      expect(bill.reload.summary).not_to eq("")
    end

    it "still returns to the creator tab when a save naming no tab is refused" do
      patch bill_path(bill), params: {summary: ""}

      expect(response).to redirect_to(
        creator_bill_creator_path(bill.id, {event_key: "legislator_votes"})
      )
    end
  end

  describe "mobile bootstrap featured bill cache invalidation" do
    include_context "with in-memory Rails.cache"

    it "evicts the cached featured bill on successful PATCH /bills/:id" do
      cache_key = "api_v1_bootstrap:botm:#{bill.sway_locale_id}"
      Rails.cache.write(cache_key, {"id" => bill.id, "title" => "Stale"})

      patch bill_path(bill), params: {summary: "An edited public summary.", return_tab: "summary", news_usage: "none"}

      expect(response).to redirect_to(summary_bill_creator_path(bill.id))
      expect(Rails.cache.read(cache_key)).to be_nil
    end

    it "evicts both previous and new locale cached featured bills when PATCH /bills/:id changes sway_locale_id" do
      other_locale = create(:sway_locale, city: "annapolis", state: "maryland", country: "united_states")
      old_key = "api_v1_bootstrap:botm:#{bill.sway_locale_id}"
      new_key = "api_v1_bootstrap:botm:#{other_locale.id}"
      Rails.cache.write(old_key, {"id" => bill.id, "title" => "Stale Old"})
      Rails.cache.write(new_key, {"id" => bill.id, "title" => "Stale New"})

      patch bill_path(bill), params: {sway_locale_id: other_locale.id}

      expect(Rails.cache.read(old_key)).to be_nil
      expect(Rails.cache.read(new_key)).to be_nil
    end

    it "preserves the cached featured bill on refused PATCH /bills/:id" do
      cache_key = "api_v1_bootstrap:botm:#{bill.sway_locale_id}"
      Rails.cache.write(cache_key, {"id" => bill.id, "title" => "Stale"})

      patch bill_path(bill), params: {summary: "", return_tab: "summary"}

      expect(response).to redirect_to(summary_bill_creator_path(bill.id))
      expect(Rails.cache.read(cache_key)).to eq({"id" => bill.id, "title" => "Stale"})
    end

    it "evicts the cached featured bill on DELETE /bills/:id" do
      cache_key = "api_v1_bootstrap:botm:#{bill.sway_locale_id}"
      Rails.cache.write(cache_key, {"id" => bill.id, "title" => "Stale"})

      delete bill_path(bill)

      expect(response).to redirect_to(new_bill_creator_path)
      expect(Rails.cache.read(cache_key)).to be_nil
    end

    it "evicts the cached featured bill on POST /bills" do
      cache_key = "api_v1_bootstrap:botm:#{sway_locale.id}"
      Rails.cache.write(cache_key, {"id" => 999, "title" => "Stale"})

      post bills_path, params: {
        external_id: "NEW-BOTM-1",
        title: "Newly Created Bill",
        chamber: "council",
        status: "committee",
        summary: "Initial bill summary",
        introduced_date_time_utc: 1.day.ago.iso8601,
        link: "https://example.com/bill-new-botm-1",
        sway_locale_id: sway_locale.id,
        legislator_id: sway_locale.legislators.first.id
      }

      expect(response).to have_http_status(:found)
      expect(Rails.cache.read(cache_key)).to be_nil
    end

    it "evicts the cached featured bill on POST /bills/:id/paste_summary" do
      cache_key = "api_v1_bootstrap:botm:#{bill.sway_locale_id}"
      Rails.cache.write(cache_key, {"id" => bill.id, "title" => "Stale"})
      allow_any_instance_of(PasteSummaryService).to receive(:call).and_return([:persisted, []])

      post "/bills/#{bill.id}/paste_summary", params: {summary_json: "{}"}

      expect(response).to redirect_to(summary_bill_creator_path(id: bill.id))
      expect(Rails.cache.read(cache_key)).to be_nil
    end

    it "evicts the cached featured bill when POST /bills/:id/restore_summary_revision restores a published summary" do
      revision = BillSummaryRevision.create!(
        bill: bill,
        summary_markdown: "Restored published summary",
        origin: "operator_edit",
        publication_role: "published",
        review_state: "reviewed"
      )
      cache_key = "api_v1_bootstrap:botm:#{bill.sway_locale_id}"
      Rails.cache.write(cache_key, {"id" => bill.id, "title" => "Stale"})

      post "/bills/#{bill.id}/restore_summary_revision", params: {revision_id: revision.id, news_usage: "none"}

      expect(response).to redirect_to(summary_bill_creator_path(bill))
      expect(Rails.cache.read(cache_key)).to be_nil
    end
  end
end

RSpec.describe "Bills public testimony props", type: :request do
  include_context "SessionDouble"
  include_context "Setup"

  let!(:sway_locale_and_user) { setup }
  let(:sway_locale) { sway_locale_and_user.first }
  let(:user) { sway_locale_and_user.last }
  let(:bill) { create(:bill, sway_locale:, legislator: sway_locale.legislators.first) }

  # @lat: [[testimony-letters#Selecting browsable constituent letters]]
  it "includes public_testimony_counts on initial visit and omits public_testimony_letters until requested" do
    get "/bills/#{bill.id}"

    expect(response).to have_http_status(:ok)
    expect(inertia).to render_component(Pages::BILL)
    expect(inertia.props[:public_testimony_counts]).to eq(
      {"total" => 0, "support" => 0, "oppose" => 0, "neutral" => 0}
    )
    expect(inertia.props.keys).not_to include("public_testimony_letters")
    expect(inertia.props.keys).not_to include(:public_testimony_letters)

    inertia_versioned_reload_only("public_testimony_letters")

    expect(response).to have_http_status(:ok)
    expect(inertia.props[:public_testimony_letters]).to eq([])
  end

  # @lat: [[testimony-letters#Selecting browsable constituent letters]]
  context "when the bill has browsable constituent letters" do
    let(:provisioning) do
      create(
        :bill_llm_provisioning,
        bill:,
        cleaned_testimony: {
          "text" => "Header info\nFrom: test@example.com\n\nI strongly support this bill for our community.",
          "letters" => [
            {
              "position" => 1,
              "source_kind" => "person_speaking_for_self",
              "stance" => "support",
              "characters" => 71,
              "character_offset" => 12
            }
          ]
        }
      )
    end

    before { provisioning }

    it "delivers counts eagerly and delivers serialized letters on partial reload" do
      get "/bills/#{bill.id}"

      expect(response).to have_http_status(:ok)
      expect(inertia.props[:public_testimony_counts]).to eq(
        {"total" => 1, "support" => 1, "oppose" => 0, "neutral" => 0}
      )
      expect(inertia.props.keys).not_to include("public_testimony_letters")

      inertia_versioned_reload_only("public_testimony_letters")

      expect(response).to have_http_status(:ok)
      letters = inertia.props[:public_testimony_letters]
      expect(letters).to be_an(Array)
      expect(letters.length).to eq(1)
      expect(letters.first).to eq(
        {
          "position" => 1,
          "label" => "Constituent Letter #1",
          "stance" => "support",
          "body_text" => "I strongly support this bill for our community."
        }
      )
      expect(letters.first["body_text"]).not_to include("test@example.com")
    end

    it "omits public_testimony_letters on JSON requests when X-Sway-Omit-Props includes public_testimony_letters" do
      get "/bills/#{bill.id}", headers: {
        "Accept" => "application/json",
        "X-Sway-Omit-Props" => "public_testimony_letters"
      }

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["public_testimony_counts"]).to eq(
        {"total" => 1, "support" => 1, "oppose" => 0, "neutral" => 0}
      )
      expect(body).not_to have_key("public_testimony_letters")
    end

    # @lat: [[testimony-letters#Reading the letters inside a testimony bundle#Presenting public testimony on bill pages#Signed-out readers receive no public testimony]]
    context "when the reader is signed out" do
      before { session_hash.delete(:user_id) }

      it "sends no public testimony counts or letters to the bill page" do
        get "/bills/#{bill.id}"

        expect(response).to have_http_status(:ok)
        expect(inertia).to render_component(Pages::BILL)
        expect(inertia.props[:public_testimony_counts]).to be_nil

        inertia_versioned_reload_only("public_testimony_letters")

        expect(response).to have_http_status(:ok)
        expect(inertia.props[:public_testimony_letters]).to be_nil
        expect(response.body).not_to include("I strongly support this bill for our community.")
      end

      it "sends no public testimony counts or letters on JSON requests" do
        get "/bills/#{bill.id}", headers: {"Accept" => "application/json"}

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["public_testimony_counts"]).to be_nil
        expect(body["public_testimony_letters"]).to be_nil
        expect(response.body).not_to include("I strongly support this bill for our community.")
      end
    end

    it "allows an admin to manually override a testimony letter's stance via PATCH /bills/:id/testimony_letter_stance" do
      patch testimony_letter_stance_bill_path(bill), params: {position: 1, stance: "oppose"}

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      updated_cleaned = provisioning.reload.cleaned_testimony
      expect(updated_cleaned["letters"].first["stance"]).to eq("oppose")
      expect(updated_cleaned["letters"].first["stance_override"]).to eq(true)
      expect(updated_cleaned["counts"]["stance_oppose_count"]).to eq(1)
      expect(updated_cleaned["counts"]["stance_support_count"]).to eq(0)
    end

    it "redirects back to HTTP_REFERER when overriding a testimony letter's stance" do
      patch testimony_letter_stance_bill_path(bill),
        params: {position: 1, stance: "oppose"},
        headers: {"HTTP_REFERER" => "http://www.example.com/bills/#{bill.id}"}

      expect(response).to redirect_to("/bills/#{bill.id}")
    end

    it "returns 422 when position is missing, negative, or non-integer" do
      patch testimony_letter_stance_bill_path(bill), params: {stance: "oppose"}
      expect(response).to have_http_status(:unprocessable_content)

      patch testimony_letter_stance_bill_path(bill), params: {position: "abc", stance: "oppose"}
      expect(response).to have_http_status(:unprocessable_content)

      patch testimony_letter_stance_bill_path(bill), params: {position: -1, stance: "oppose"}
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "allows an admin to manually remove a testimony letter via excluded: true and recomputes stance counts" do
      patch testimony_letter_stance_bill_path(bill), params: {position: 1, excluded: true}

      expect(response).to redirect_to(positions_bill_creator_path(bill))
      expect(flash[:notice]).to eq("Removed testimony letter from #{bill.external_id}.")
      updated_cleaned = provisioning.reload.cleaned_testimony
      expect(updated_cleaned["letters"].first["excluded"]).to eq(true)
      expect(updated_cleaned["letters"].first["stance_override"]).to eq(true)
      expect(updated_cleaned["counts"]["stance_support_count"]).to eq(0)
    end
  end

  # @lat: [[news-manual-evidence-ui#Historical legacy restoration#Editor review and explicit publication]]
  # @lat: [[bill-creator-summary-tab#The Bill Creator summary tab#Planned recoverable summary history]]
  describe "cross-bill draft_revision_id isolation on GET /admin/bill_creator/:id/summary" do
    it "refuses to load a draft_revision_id belonging to another bill or a nonexistent id" do
      other_bill = create(:bill, sway_locale:, legislator: sway_locale.legislators.first, external_id: "OTHER-REV-1")
      foreign_draft = BillSummaryRevision.create!(
        bill: other_bill,
        summary_markdown: "Foreign secret draft",
        origin: "operator_edit",
        publication_role: "draft",
        review_state: "reviewed"
      )

      get summary_bill_creator_path(bill, draft_revision_id: foreign_draft.id)
      expect(response).to have_http_status(:ok)
      expect(inertia.props[:review_draft_revision]).to be_nil
      expect(response.body).not_to include("Foreign secret draft")

      get summary_bill_creator_path(bill, draft_revision_id: 999_999)
      expect(response).to have_http_status(:ok)
      expect(inertia.props[:review_draft_revision]).to be_nil
    end
  end
end
