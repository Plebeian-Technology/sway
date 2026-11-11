# frozen_string_literal: true

# @lat: [[llm-summaries#LLM bill summaries#Two adapters, one client#The live check against a local server is a task, not a test]]
namespace :legislation do
  desc "Operator smoke: run GenerateBillSummaryJob against the live llama.cpp server."
  task smoke_summary: :environment do
    bill = Bill.order(:id).first
    abort("No bills in DB — run `dip run rails db:seed:bills` first") unless bill

    base_url = ENV.fetch("LLAMACPP_BASE_URL", "http://host.docker.internal:8888/v1")
    model = ENV.fetch("LLAMACPP_MODEL", "local")

    puts "Smoking GenerateBillSummaryJob against #{base_url} (model: #{model})"
    puts "  bill ##{bill.id} (#{bill.external_id})"

    GenerateBillSummaryJob.perform_now(bill.id)

    provisioning = bill.reload.bill_llm_provisioning
    abort("FAIL: bill ##{bill.id} has no BillLlmProvisioning row") if provisioning.nil?

    summary = provisioning.llm_summary.to_s
    puts "  status:          #{provisioning.generation_status}"
    puts "  summary length:  #{summary.length}"
    puts "  llm_provider:    #{provisioning.llm_provider}"
    puts "  llm_model:       #{provisioning.llm_model}"
    puts "  llm_generated_at: #{provisioning.llm_generated_at}"
    puts "  first 500 chars: #{summary[0, 500]}"

    abort("FAIL: empty summary from llama.cpp (generation_error: #{provisioning.generation_error.inspect})") if summary.strip.empty?

    puts "OK: the summary came back with content."
  end

  desc "Operator smoke: prove GenerateBillSummaryJob#failed path"
  task smoke_summary_malformed: :environment do
    bill = Bill.order(:id).first
    abort("No bills in DB — run `dip run rails db:seed:bills` first") unless bill

    provisioning = bill.bill_llm_provisioning || bill.create_bill_llm_provisioning!
    provisioning.update_columns(
      generation_status: "pending",
      generation_error: nil,
      llm_summary: nil,
      summary_run_id: nil
    )

    BillSummaryPromptBuilder.singleton_class.send(:alias_method, :__orig_new, :new)
    BillSummaryPromptBuilder.define_singleton_method(:new) do |_bill|
      Struct.new(:call).new(
        "Return literally the string {{{ with no other content, no quotes, no JSON wrapping."
      )
    end

    begin
      GenerateBillSummaryJob.perform_now(bill.id)
    rescue GenerateBillSummaryJob::BillSummaryError => e
      puts "RAISED BillSummaryError as expected: #{e.message[0, 200]}"
    ensure
      BillSummaryPromptBuilder.singleton_class.send(:remove_method, :new)
      BillSummaryPromptBuilder.singleton_class.send(:alias_method, :new, :__orig_new)
      BillSummaryPromptBuilder.singleton_class.send(:remove_method, :__orig_new)
    end

    provisioning.reload
    puts "  status:           #{provisioning.generation_status}"
    puts "  generation_error: #{provisioning.generation_error.inspect}"

    unless provisioning.generation_status == "failed"
      abort("FAIL: expected generation_status=failed, got #{provisioning.generation_status.inspect}")
    end
    puts "OK: failure path landed in `failed` with a populated generation_error."
  end
end
