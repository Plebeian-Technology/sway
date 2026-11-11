# frozen_string_literal: true

require "rails_helper"

# @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
RSpec.describe "BackfillBillCategoriesJob", type: :model do
  # Look the class up lazily, so this file still loads if the production class
  # is not there yet.
  let(:job_class) { Object.const_get("BackfillBillCategoriesJob") }

  # Active categories, used by the stubbed LLM adapter responses below.
  let!(:cat_housing) { create(:category, name: "Housing", slug: "housing", active: true) }
  let!(:cat_health) { create(:category, name: "Health", slug: "health", active: true) }
  let!(:cat_economy) { create(:category, name: "Economy", slug: "economy", active: true) }

  # Stub the LLM adapter so no live network call is made.
  let(:adapter) { instance_double("Llm::ClaudeAdapter", provider_label: "claude") }

  # @lat: [[settings-and-secrets#Settings and secrets]]
  around do |example|
    with_app_config(:llm, llm_provider: "claude") { example.run }
  end

  before do
    allow(Object.const_get("Llm::Client")).to receive(:build).and_return(adapter)
    allow(adapter).to receive(:generate_bill_categories).and_return(
      {"categories" => ["Housing", "Health"]}
    )
  end

  describe "#perform — assigns 1–3 active categories to uncategorized summarized bills" do
    let(:bill) { create(:bill) }
    let!(:provisioning) { create(:bill_llm_provisioning, :completed, bill: bill) }

    it "assigns 1–3 active categories after perform" do
      job_class.new.perform
      expect(bill.reload.categories.count).to be_between(1, 3)
    end

    it "assigns only active categories" do
      job_class.new.perform
      expect(bill.reload.categories).to all(satisfy { |c| c.active? })
    end
  end

  describe "#perform — skips bills with no llm_summary" do
    let(:bill_without_summary) { create(:bill) }
    let!(:provisioning_no_summary) do
      create(:bill_llm_provisioning, bill: bill_without_summary, llm_summary: nil,
        generation_status: "pending")
    end

    it "does not assign categories to a bill with no llm_summary" do
      job_class.new.perform
      expect(bill_without_summary.reload.categories.count).to eq(0)
    end
  end

  describe "#perform — skips bills already carrying ≥1 ACTIVE category" do
    let(:bill_already_categorized) { create(:bill) }
    let!(:provisioning_categorized) do
      create(:bill_llm_provisioning, :completed, bill: bill_already_categorized)
    end
    let!(:existing_join) do
      bill_category_class = Object.const_get("BillCategory")
      bill_category_class.create!(bill: bill_already_categorized, category: cat_housing)
    end

    it "does not make an LLM call for an already-categorized bill" do
      # The adapter should NOT be called for bills that already have active categories.
      expect(adapter).not_to receive(:generate_bill_categories)
      job_class.new.perform
    end

    it "does not change the existing category count for an already-categorized bill" do
      job_class.new.perform
      expect(bill_already_categorized.reload.categories.count).to eq(1)
    end
  end

  describe "#perform — idempotency: second run is a no-op (R9)" do
    let(:bill) { create(:bill) }
    let!(:provisioning) { create(:bill_llm_provisioning, :completed, bill: bill) }

    it "does not change category count on the second run" do
      job_class.new.perform
      initial_count = bill.reload.categories.count
      initial_ids = bill.category_ids.sort

      job_class.new.perform
      expect(bill.reload.categories.count).to eq(initial_count)
      expect(bill.reload.category_ids.sort).to eq(initial_ids)
    end

    it "does not call the LLM adapter on the second run (categories already assigned)" do
      job_class.new.perform
      expect(adapter).not_to receive(:generate_bill_categories)
      job_class.new.perform
    end
  end

  describe "#perform — summarized bill whose ONLY category is active:false is re-categorized" do
    # @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
    let(:bill_with_only_inactive_category) { create(:bill) }
    let!(:provisioning_inactive) do
      create(:bill_llm_provisioning, :completed, bill: bill_with_only_inactive_category)
    end
    let!(:inactive_category) do
      create(:category, name: "Deprecated Topic", slug: "deprecated-topic", active: false)
    end
    let!(:inactive_join) do
      bill_category_class = Object.const_get("BillCategory")
      bill_category_class.create!(
        bill: bill_with_only_inactive_category,
        category: inactive_category
      )
    end

    before do
      # The adapter returns active categories for this bill.
      allow(adapter).to receive(:generate_bill_categories).and_return(
        {"categories" => ["Housing"]}
      )
    end

    it "recognizes the bill as uncategorized (sole category is inactive) and re-categorizes it" do
      job_class.new.perform
      active_cat_names = bill_with_only_inactive_category.reload.categories
        .select(&:active?).map(&:name)
      expect(active_cat_names).to include("Housing")
    end

    it "ends with 1–3 active categories after re-categorization" do
      job_class.new.perform
      active_categories = bill_with_only_inactive_category.reload.categories.select(&:active?)
      expect(active_categories.count).to be_between(1, 3)
    end
  end

  describe "#perform — per-bill LLM-failure isolation" do
    # One bad bill must not abort the whole backfill batch.
    let(:good_bill) { create(:bill) }
    let(:bad_bill) { create(:bill) }
    let!(:good_provisioning) { create(:bill_llm_provisioning, :completed, bill: good_bill) }
    let!(:bad_provisioning) { create(:bill_llm_provisioning, :completed, bill: bad_bill) }

    before do
      # The call for bad_bill raises Llm::SchemaError; the call for good_bill
      # returns a valid payload. The order the bills arrive in is not under our
      # control, so the stub counts calls instead.
      call_count = 0
      allow(adapter).to receive(:generate_bill_categories) do |**_|
        call_count += 1
        if call_count == 1
          raise Llm::SchemaError, "no valid categories returned"
        else
          {"categories" => ["Housing"]}
        end
      end
      allow(SwayLogging).to receive(:log_exception)
    end

    it "continues after one bill's LLM call raises Llm::SchemaError" do
      expect { job_class.new.perform }.not_to raise_error
    end

    it "logs the per-bill failure via SwayLogging" do
      job_class.new.perform
      expect(SwayLogging).to have_received(:log_exception).with(
        "backfill_bill_categories.bill_failed",
        hash_including(:exception, :bill_id)
      )
    end

    it "categorizes the surviving bill even when one fails" do
      job_class.new.perform
      # At least one of the two bills should be categorized (the non-failing one).
      categorized_count = [good_bill, bad_bill].count { |b| b.reload.categories.any? }
      expect(categorized_count).to be >= 1
    end
  end

  # @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
  describe "#perform — unmatchable bill is attempted once" do
    let(:bill) { create(:bill) }
    let!(:provisioning) { create(:bill_llm_provisioning, :completed, bill: bill) }

    # The model answers, but with nothing in the active taxonomy.
    before do
      allow(adapter).to receive(:generate_bill_categories).and_return(
        {"categories" => ["Astronomy"]}
      )
    end

    it "stamps categories_unmatched_at rather than generation_status failed" do
      job_class.new.perform

      expect(provisioning.reload.categories_unmatched_at).to be_present
    end

    # That earlier fix has to stay fixed: flipping the row to failed is what
    # stranded the summary in a UI branch that never renders it.
    it "leaves generation_status untouched" do
      expect { job_class.new.perform }
        .not_to change { provisioning.reload.generation_status }
    end

    it "makes no further LLM call on the next boot" do
      job_class.new.perform
      expect(adapter).to have_received(:generate_bill_categories).once

      job_class.new.perform
      expect(adapter).to have_received(:generate_bill_categories).once
    end

    # Put the bill back in play. The stamp means "could not be matched against
    # the taxonomy as it stood then", so any write to the taxonomy clears it.
    # The admin action most likely to fix the problem is the same one that
    # re-arms the bill, with no separate button to press.
    it "is retried after the active taxonomy changes" do
      job_class.new.perform
      expect(adapter).to have_received(:generate_bill_categories).once

      BillLlmProvisioning.where.not(categories_unmatched_at: nil)
        .update_all(categories_unmatched_at: nil)

      job_class.new.perform
      expect(adapter).to have_received(:generate_bill_categories).twice
    end

    # @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
    it "asks again once the summary it judged has been replaced" do
      job_class.new.perform
      expect(adapter).to have_received(:generate_bill_categories).once

      # What a regeneration or a paste leaves behind: newer text, older verdict.
      provisioning.reload.update_columns(
        llm_summary: "A different summary, bought after the stamp.",
        llm_generated_at: 1.minute.from_now
      )
      allow(adapter).to receive(:generate_bill_categories).and_return(
        {"categories" => ["Housing"]}
      )

      job_class.new.perform

      expect(bill.reload.categories.map(&:name)).to include("Housing")
    end

    # @lat: [[boot-time-backfills#Why a stamped bill costs nothing on the next boot]]
    it "stays excluded while the stamp is newer than the summary" do
      provisioning.update_columns(
        llm_generated_at: 2.days.ago,
        categories_unmatched_at: 1.day.ago
      )

      job_class.new.perform

      expect(adapter).not_to have_received(:generate_bill_categories)
    end

    # A row whose summary has no known age. Re-arming it would buy the same
    # no-match answer on every boot, forever.
    it "stays excluded when the summary has no timestamp at all" do
      provisioning.update_columns(
        llm_generated_at: nil,
        categories_unmatched_at: 1.day.ago
      )

      job_class.new.perform

      expect(adapter).not_to have_received(:generate_bill_categories)
    end

    # @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
    it "does not stamp when the ADAPTER raises — that failure is transient" do
      allow(adapter).to receive(:generate_bill_categories)
        .and_raise(Llm::SchemaError, "malformed response")

      job_class.new.perform

      expect(provisioning.reload.categories_unmatched_at).to be_nil
    end

    it "retries a transient adapter failure on the next boot" do
      allow(adapter).to receive(:generate_bill_categories)
        .and_raise(Llm::SchemaError, "malformed response")
      job_class.new.perform

      allow(adapter).to receive(:generate_bill_categories).and_return(
        {"categories" => ["Housing"]}
      )
      job_class.new.perform

      expect(bill.reload.categories.map(&:name)).to include("Housing")
    end
  end

  describe "source assertions (structure guards)" do
    let(:source) { Rails.root.join("app", "jobs", "backfill_bill_categories_job.rb").read }

    it "declares limits_concurrency to: 1 with a proc key for single-flight guard (T-60-11)" do
      expect(source).to match(/limits_concurrency to: 1/)
      expect(source).to include('"backfill_bill_categories"')
      expect(source).to include("on_conflict: :discard")
    end

    it "uses a proc key matching the repo convention ->(*_args, **_kwargs) { ... }" do
      expect(source).to match(/key:\s*->\(\*_args,\s*\*\*_kwargs\)/)
    end

    it "has return if uncategorized.none? as the idempotency gate BEFORE any adapter build" do
      return_pos = source.index("return if uncategorized.none?")
      adapter_pos = source.index("Llm::Client.build")
      expect(return_pos).not_to be_nil
      expect(adapter_pos).not_to be_nil
      expect(return_pos).to be < adapter_pos
    end

    it "loads active_categories once outside find_each (no N+1 per bill)" do
      # `active_categories = Category.where(active: true).order(:name).to_a` has
      # to appear before `uncategorized.find_each` in the source, and only once.
      ac_matches = source.scan("Category.where(active: true).order(:name).to_a")
      expect(ac_matches.count).to eq(1)
      ac_pos = source.index("Category.where(active: true).order(:name).to_a")
      find_each_pos = source.index("uncategorized.find_each")
      expect(ac_pos).to be < find_each_pos
    end
  end

  describe "#perform — T-60-11: a per-bill RecordNotUnique does not abort the batch" do
    # @lat: [[testing-the-toolchain#A guard asserts behaviour rather than source text]]
    let(:first_bill) { create(:bill) }
    let(:second_bill) { create(:bill) }
    let!(:first_provisioning) { create(:bill_llm_provisioning, :completed, bill: first_bill) }
    let!(:second_provisioning) { create(:bill_llm_provisioning, :completed, bill: second_bill) }

    before do
      call_count = 0
      allow(adapter).to receive(:generate_bill_categories) do |**_|
        call_count += 1
        raise ActiveRecord::RecordNotUnique.new("duplicate key value violates unique constraint") if call_count == 1
        {"categories" => ["Housing"]}
      end
      allow(SwayLogging).to receive(:log_exception)
    end

    it "does not raise" do
      expect { job_class.new.perform }.not_to raise_error
    end

    it "logs the per-bill RecordNotUnique via SwayLogging" do
      job_class.new.perform
      expect(SwayLogging).to have_received(:log_exception).with(
        "backfill_bill_categories.bill_failed",
        hash_including(:exception, :bill_id)
      )
    end

    it "still categorizes the bill that comes after the one that raised" do
      job_class.new.perform
      expect(first_bill.reload.categories).to be_empty
      expect(second_bill.reload.categories).not_to be_empty
    end
  end

  describe "#perform — C-W-01: a per-bill RecordInvalid does not abort the batch" do
    # @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
    let(:good_bill) { create(:bill) }
    let(:bad_bill) { create(:bill) }
    let!(:good_provisioning) { create(:bill_llm_provisioning, :completed, bill: good_bill) }
    let!(:bad_provisioning) { create(:bill_llm_provisioning, :completed, bill: bad_bill) }

    before do
      call_count = 0
      allow(adapter).to receive(:generate_bill_categories) do |**_|
        call_count += 1
        # First bill raises the previously-uncaught RecordInvalid; second returns valid data.
        raise ActiveRecord::RecordInvalid.new(BillCategory.new) if call_count == 1
        {"categories" => ["Housing"]}
      end
      allow(SwayLogging).to receive(:log_exception)
    end

    it "does not raise — the narrow rescue would have aborted the whole batch" do
      expect { job_class.new.perform }.not_to raise_error
    end

    it "logs the per-bill RecordInvalid via SwayLogging" do
      job_class.new.perform
      expect(SwayLogging).to have_received(:log_exception).with(
        "backfill_bill_categories.bill_failed",
        hash_including(:exception, :bill_id)
      )
    end

    it "still categorizes the surviving bill" do
      job_class.new.perform
      categorized = [good_bill, bad_bill].count { |b| b.reload.categories.any? }
      expect(categorized).to be >= 1
    end
  end

  describe "#perform — I-11: a summarized-but-FAILED bill is excluded" do
    # @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
    let(:bill_failed) { create(:bill) }
    let!(:provisioning_failed) do
      create(:bill_llm_provisioning, :failed, bill: bill_failed,
        llm_summary: "This summarized fine, but categorization failed.")
    end

    it "does not make an LLM call for a summarized-but-failed bill" do
      expect(adapter).not_to receive(:generate_bill_categories)
      job_class.new.perform
    end

    it "does not assign categories to a summarized-but-failed bill" do
      job_class.new.perform
      expect(bill_failed.reload.categories.count).to eq(0)
    end
  end

  describe "#perform — W-02: an empty active taxonomy skips the adapter entirely" do
    # @lat: [[explanation/boot-time-backfills#Why a stamped bill costs nothing on the next boot#The category backfill buys only a missing active verdict]]
    let(:bill) { create(:bill) }
    let!(:provisioning) { create(:bill_llm_provisioning, :completed, bill: bill) }

    before { Object.const_get("Category").update_all(active: false) }

    it "never builds or calls the LLM adapter when no active categories exist" do
      expect(Object.const_get("Llm::Client")).not_to receive(:build)
      expect(adapter).not_to receive(:generate_bill_categories)
      job_class.new.perform
    end

    it "leaves the bill uncategorized (no active categories assigned)" do
      job_class.new.perform
      expect(bill.reload.categories.select(&:active?)).to be_empty
    end
  end

  describe "OpenRouter routing from the selected summary model" do
    let(:bill) { create(:bill) }
    let!(:provisioning) { create(:bill_llm_provisioning, :completed, bill: bill) }
    let(:openrouter_adapter) { instance_double("Llm::OpenRouterAdapter", provider_label: "openrouter") }

    [
      ["Deepseek Pro Latest", "~deepseek/deepseek-pro-latest"],
      ["Deepseek Flash Latest", "~deepseek/deepseek-flash-latest"],
      ["OpenRouter Auto", "openrouter/auto"]
    ].each do |display_name, api_model|
      it "routes #{display_name} to OpenRouter adapter with api_model #{api_model} when environment is claude" do
        with_app_config(:llm, llm_provider: "claude") do
          AdminSetting.singleton.update_columns(summarization_model: display_name)
          allow(Object.const_get("Llm::Client")).to receive(:build).with(provider: "openrouter").and_return(openrouter_adapter)

          expect(openrouter_adapter).to receive(:generate_bill_categories).with(
            prompt: anything,
            model: api_model,
            schema: anything
          ).and_return({"categories" => ["Housing"]})

          job_class.new.perform
          expect(bill.reload.categories.map(&:name)).to include("Housing")
        end
      end

      it "routes #{display_name} to OpenRouter adapter with api_model #{api_model} when environment is llamacpp" do
        with_app_config(:llm, llm_provider: "llamacpp") do
          AdminSetting.singleton.update_columns(summarization_model: display_name)
          allow(Object.const_get("Llm::Client")).to receive(:build).with(provider: "openrouter").and_return(openrouter_adapter)

          expect(openrouter_adapter).to receive(:generate_bill_categories).with(
            prompt: anything,
            model: api_model,
            schema: anything
          ).and_return({"categories" => ["Housing"]})

          job_class.new.perform
          expect(bill.reload.categories.map(&:name)).to include("Housing")
        end
      end
    end

    it "raises Llm::UnknownRouteError explicitly for an unknown route" do
      AdminSetting.singleton.update_columns(summarization_model: "nonexistent-model-xyz")

      expect {
        job_class.new.perform
      }.to raise_error(Llm::UnknownRouteError)
    end
  end
end
