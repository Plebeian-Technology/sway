# frozen_string_literal: true

require "rails_helper"
require "support/openrouter_measurement_report"

RSpec.describe Llm::OpenRouterAdapter, "live OpenRouter API integration", :integration do
  describe "deterministic request and measurement contracts" do
    it "sends both production schemas with additionalProperties false" do
      adapter = described_class.new
      client = double
      prompt = Llm::PromptPayload.new(system_prompt: "system", user_message: "user")
      captured = []
      route = Llm::ModelCatalog.fetch("Deepseek Pro Latest")
      responses = [
        {
          "choices" => [{"finish_reason" => "stop", "message" => {"content" => {summary_markdown: "Summary"}.to_json}}],
          "openrouter_metadata" => {"endpoints" => {"available" => [{"provider" => "DeepSeek", "selected" => true}]}},
          "model" => route.api_model
        },
        {
          "choices" => [{"finish_reason" => "stop", "message" => {"content" => {draft_org_positions: []}.to_json}}],
          "openrouter_metadata" => {"endpoints" => {"available" => [{"provider" => "DeepSeek", "selected" => true}]}},
          "model" => route.api_model
        }
      ]
      allow(adapter).to receive(:client).and_return(client)
      allow(client).to receive(:chat) do |parameters:|
        captured << parameters
        responses.shift
      end

      adapter.generate_bill_summary(prompt: prompt, model: route.api_model, schema: BILL_SUMMARY_SCHEMA_HASH)
      adapter.generate_bill_positions(prompt: prompt, model: route.api_model, schema: BILL_POSITIONS_SCHEMA_HASH)

      expect(captured.length).to eq(2)
      expect(captured.map { |parameters| parameters.dig(:response_format, :json_schema, :schema, "additionalProperties") })
        .to eq([false, false])
      expect(captured.last.dig(:response_format, :json_schema, :schema, "properties", "draft_org_positions", "items", "additionalProperties"))
        .to be(false)
    end

    it "records requested and resolved route identity with an unestablished cache threshold" do
      report = OpenRouterMeasurementReport.build(recorded_at: Time.utc(2026, 10, 5, 12))
      route = Llm::ModelCatalog.fetch("Deepseek Pro Latest")
      choice = OpenRouterMeasurementReport.choice(label: "Deepseek Pro Latest", model: route.api_model)
      choice["schema_measurements"]["bill_summary"] = {
        "requested_model_id" => route.api_model,
        "actual_model" => route.api_model,
        "upstream_company" => "DeepSeek",
        "attempts_count" => 1,
        "first_attempt_valid_count" => 1,
        "retry_valid_count" => 0,
        "failed_count" => 0
      }
      report["choices"] << choice
      decoded = JSON.parse(JSON.generate(report))

      expect(decoded.dig("choices", 0, "requested_alias")).to eq("Deepseek Pro Latest")
      expect(decoded.dig("choices", 0, "schema_measurements", "bill_summary", "actual_model"))
        .to eq(route.api_model)
      expect(decoded.dig("choices", 0, "schema_measurements", "bill_summary", "upstream_company"))
        .to eq("DeepSeek")
      expect(decoded.dig("choices", 0, "cache_measurement", "sway_prompt_cache_reached")).to be(false)
      expect(decoded.dig("choices", 0, "cache_measurement", "cache_threshold_tokens")).to be_nil
      expect(decoded.dig("choices", 0, "cache_measurement", "cache_threshold_status")).to eq("not_established")
    end

    it "keeps prompt and credential fields out of usage snapshots" do
      snapshot = OpenRouterMeasurementReport.usage_snapshot(
        "prompt_tokens" => 120,
        "prompt_tokens_details" => {"cached_tokens" => 32},
        "api_key" => "secret",
        "prompt" => "private content"
      )

      expect(snapshot).to eq(
        "prompt_tokens" => 120,
        "prompt_tokens_details" => {"cached_tokens" => 32}
      )
    end
  end

  describe "live OpenRouter execution (opt-in)" do
    before do
      skip "RUN_LIVE_LLM_TESTS=1 not set — live spec skipped to prevent accidental API spend" unless ENV["RUN_LIVE_LLM_TESTS"] == "1"

      begin
        described_class.api_key
      rescue Llm::TransportError
        skip "OpenRouter credential is not available through EnvSecret"
      end
    end

    let(:fixture_text) { Rails.root.join("spec", "fixtures", "llm", "sample_bill_source.md").read }

    let(:bill) do
      sway_locale = create(:sway_locale, city: "Baltimore", state: "Maryland", country: "United States")
      district = create(:district, sway_locale: sway_locale)
      legislator = create(:legislator, district: district)
      create(
        :bill,
        sway_locale: sway_locale,
        legislator: legislator,
        external_id: "CB-26-0177-OR-LIVE",
        title: "Annual Lead-Paint Inspections — Rental Units Constructed Before 1978",
        status: Bill::Status::COMMITTEE,
        category: "civic",
        scheduled_release_date_utc: Date.new(2026, 6, 15)
      )
    end

    let(:prompt) do
      bill.update!(extracted_text: fixture_text)
      builder = BillSummaryPromptBuilder.new(bill)
      Llm::PromptPayload.new(system_prompt: builder.system_prompt, user_message: builder.user_message)
    end

    let(:positions_prompt) do
      bill.create_bill_llm_provisioning!(
        extracted_testimony: <<~TESTIMONY
          Maryland Tenants Union — written testimony, October 16 2025.
          We SUPPORT this bill. Annual inspections close a documented
          enforcement gap that falls hardest on tenants in lower-income
          neighborhoods.

          Greater Baltimore Apartment Association — written testimony.
          We OPPOSE the annual cadence. Biennial inspections achieve the same
          public-health outcome at roughly half the operational cost.
        TESTIMONY
      )
      builder = BillPositionsPromptBuilder.new(bill.reload)
      Llm::PromptPayload.new(system_prompt: builder.system_prompt, user_message: builder.user_message)
    end

    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#Strict JSON conformance on the pinned route]]
    # @lat: [[llm-summaries#What a third provider reached through OpenRouter exposes#Prompt caching measurement on the pinned OpenRouter route]]
    it "writes dated schema and cache observations for each catalog choice" do
      report = OpenRouterMeasurementReport.build(recorded_at: Time.current.utc)
      allow(Llm::PromptCache).to receive(:cacheable?).and_call_original

      begin
        Llm::ModelCatalog.openrouter_choices.each do |label|
          route = Llm::ModelCatalog.fetch(label)
          choice = OpenRouterMeasurementReport.choice(label: label, model: route.api_model)
          report["choices"] << choice

          summary_first = OpenRouterMeasurementReport.measured_call(
            adapter_class: described_class,
            prompt: prompt,
            model: route.api_model,
            schema: BILL_SUMMARY_SCHEMA_HASH,
            validator: BILL_SUMMARY_SCHEMA,
            method_name: :generate_bill_summary
          )
          summary_repeat = OpenRouterMeasurementReport.measured_call(
            adapter_class: described_class,
            prompt: prompt,
            model: route.api_model,
            schema: BILL_SUMMARY_SCHEMA_HASH,
            validator: BILL_SUMMARY_SCHEMA,
            method_name: :generate_bill_summary
          )
          positions = OpenRouterMeasurementReport.measured_call(
            adapter_class: described_class,
            prompt: positions_prompt,
            model: route.api_model,
            schema: BILL_POSITIONS_SCHEMA_HASH,
            validator: BILL_POSITIONS_SCHEMA,
            method_name: :generate_bill_positions
          )

          choice["schema_measurements"]["bill_summary"] = OpenRouterMeasurementReport.aggregate_schema_measurement(
            label: label,
            model: route.api_model,
            outcomes: [summary_first, summary_repeat]
          )
          choice["schema_measurements"]["bill_positions"] = OpenRouterMeasurementReport.aggregate_schema_measurement(
            label: label,
            model: route.api_model,
            outcomes: [positions]
          )
          choice["cache_measurement"]["calls"] = [
            summary_first.fetch("call"),
            summary_repeat.fetch("call")
          ]
          choice["cache_measurement"]["cache_threshold_status"] = "not_established"
        end
      ensure
        report["finished_at"] = Time.current.utc.iso8601
        report_path = OpenRouterMeasurementReport.write(report)
        puts "OpenRouter measurement report: #{report_path}"
      end

      expect(Llm::PromptCache).not_to have_received(:cacheable?)
      expect(report["choices"].pluck("requested_alias"))
        .to eq(Llm::ModelCatalog.openrouter_choices)
      report["choices"].each do |choice|
        %w[bill_summary bill_positions].each do |schema_name|
          measurement = choice.dig("schema_measurements", schema_name)
          expect(measurement["first_attempt_valid_count"] + measurement["retry_valid_count"]).to be > 0,
            "#{choice["requested_alias"]} produced no schema-valid #{schema_name}; see the saved report"
          expect(measurement["actual_model"]).to be_present,
            "#{choice["requested_alias"]} has no resolved model for #{schema_name}; see the saved report"
          expect(measurement["upstream_company"]).to be_present,
            "#{choice["requested_alias"]} has no permitted upstream for #{schema_name}; see the saved report"
          measurement["attempts"].select { |attempt| attempt["status"] == "valid" }.each do |attempt|
            expect(attempt["actual_model"]).to be_present,
              "#{choice["requested_alias"]} has a valid #{schema_name} response without model attribution"
            expect(attempt["upstream_company"]).to be_present,
              "#{choice["requested_alias"]} has a valid #{schema_name} response without upstream attribution"
          end
          puts [
            "OpenRouter schema measurement",
            "requested=#{choice["requested_alias"]}",
            "model=#{measurement["actual_model"]}",
            "upstream=#{measurement["upstream_company"]}",
            "schema=#{schema_name}",
            "first_valid=#{measurement["first_attempt_valid_count"]}",
            "retry_valid=#{measurement["retry_valid_count"]}",
            "failed=#{measurement["failed_count"]}"
          ].join(" ")
        end
      end
    end
  end
end
