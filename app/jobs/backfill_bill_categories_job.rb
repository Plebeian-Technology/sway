# frozen_string_literal: true

# @lat: [[backfill-bill-categories-scope#The taxonomy-mismatch case no longer marks a bill "failed"]]
class BackfillBillCategoriesJob < ApplicationJob
  queue_as :background

  # @lat: [[backfill-bill-categories-scope#Concurrency: the fixed proc key]]
  limits_concurrency to: 1,
    key: ->(*_args, **_kwargs) { "backfill_bill_categories" },
    on_conflict: :discard

  def perform
    # @lat: [[backfill-bill-categories-scope#The taxonomy-mismatch case no longer marks a bill "failed"]]
    uncategorized = Bill
      .joins(:bill_llm_provisioning)
      .where.not(bill_llm_provisionings: {llm_summary: nil})
      .where.not(id: BillCategory.joins(:category).where(categories: {active: true}).select(:bill_id))
      .where(
        "bill_llm_provisionings.generation_status IS NULL OR bill_llm_provisionings.generation_status != ?",
        "failed"
      )
      .where(
        "bill_llm_provisionings.categories_unmatched_at IS NULL OR " \
        "bill_llm_provisionings.categories_unmatched_at < bill_llm_provisionings.llm_generated_at"
      )

    return if uncategorized.none?

    # @lat: [[backfill-bill-categories-scope#Why the empty-active-taxonomy bail happens before the adapter is built]]
    active_categories = Category.where(active: true).order(:name).to_a
    if active_categories.empty?
      SwayLogging.warn(
        "backfill_bill_categories.no_active_categories",
        message: "no active categories — skipping backfill"
      )
      return
    end

    # @lat: [[llm-job-model-resolution-per-perform#Why the model is re-read on every perform, not memoized]]
    route = Llm::RouteResolver.resolve(purpose: :summary)
    adapter = Llm::Client.build(provider: route.provider.to_s)
    model = route.api_model
    category_kwargs = {}
    category_kwargs[:reasoning_effort] = route.reasoning_effort if adapter.provider_label == "openrouter" && route.reasoning_effort.present?

    uncategorized.find_each do |bill|
      prompt = BillCategoryPromptBuilder.new(bill, active_categories: active_categories).payload
      parsed = adapter.generate_bill_categories(
        prompt: prompt,
        model: model,
        schema: BILL_CATEGORIES_SCHEMA_HASH,
        **category_kwargs
      )

      # @lat: [[backfill-bill-categories-scope#Why the Llm::SchemaError rescue wraps only the assigner]]
      begin
        BillCategoryAssigner.new(bill, parsed["categories"], active_categories).call
      rescue Llm::SchemaError => e
        mark_categories_unmatched!(bill, e)
      end
    rescue => e
      # @lat: [[backfill-bill-categories-scope#Why the per-bill rescue is broad, and what that trades away]]
      SwayLogging.log_exception(
        "backfill_bill_categories.bill_failed",
        exception: e,
        bill_id: bill.id
      )
    end
  end

  private

  # @lat: [[bills-category-filter#Bills category filter#Why a bill matches on ANY category]]
  # @lat: [[backfill-bill-categories-scope#Why the unmatched-stamp log is at warn, not silent]]
  def mark_categories_unmatched!(bill, error)
    bill.bill_llm_provisioning&.update_columns(categories_unmatched_at: Time.current)
    SwayLogging.warn(
      "backfill_bill_categories.unmatched",
      bill_id: bill.id,
      message: "constrained prompt matched no active category; excluded until the taxonomy changes: " \
        "#{error.message.to_s[0, 200]}"
    )
  end
end
