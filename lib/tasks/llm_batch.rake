# frozen_string_literal: true

namespace :sway do
  namespace :llm do
    desc "Submit a small batch of real dumped Sway prompts through Llm::ClaudeBatchService on claude-sonnet-5 " \
      "and prove the batch API path end-to-end. Realistic cost for the default " \
      "3-item limit: well under $0.01 (Sonnet 5.5 batch pricing is $1/$5 per MTok, half the $2/$10 list price). " \
      "Requires ANTHROPIC_API_KEY and RUN_LIVE_LLM_TESTS=1; BATCH_PROVE_MODEL and BATCH_PROVE_LIMIT override the defaults."
    task prove_batch: :environment do
      limit = Integer(ENV.fetch("BATCH_PROVE_LIMIT", "3"))

      unless ENV["RUN_LIVE_LLM_TESTS"] == "1"
        abort <<~MESSAGE
          sway:llm:prove_batch refuses to run without RUN_LIVE_LLM_TESTS=1 -- this task makes
          real, billed Anthropic API calls. Sonnet 5.5 batch pricing is $1/$5 per MTok (half the
          $2/$10 list price); a #{limit}-item run of real Sway prompts costs well under $0.01.
          Re-run as:

            RUN_LIVE_LLM_TESTS=1 dip run bundle exec rake sway:llm:prove_batch
        MESSAGE
      end

      if EnvSecret.read("ANTHROPIC_API_KEY").nil?
        abort "sway:llm:prove_batch: ANTHROPIC_API_KEY is not set (or is blank) in this process's environment."
      end

      model = ENV.fetch("BATCH_PROVE_MODEL", "claude-sonnet-5-5")

      manifest_path = Rails.root.join("eval", "manifest.json")
      unless manifest_path.exist?
        abort "eval/manifest.json not found -- run `bundle exec rake sway:eval:dump` first. " \
          "sway:llm:prove_batch reads real dumped Sway prompts from that manifest; it does not build its own."
      end

      manifest = JSON.parse(manifest_path.read)
      entries = manifest.values.first(limit)
      if entries.empty?
        abort "eval/manifest.json has no entries -- run `bundle exec rake sway:eval:dump` first."
      end

      schema_hash_for = {"summary" => BILL_SUMMARY_SCHEMA_HASH, "positions" => BILL_POSITIONS_SCHEMA_HASH}
      validation_schema_for = {"summary" => BILL_SUMMARY_SCHEMA, "positions" => BILL_POSITIONS_SCHEMA}

      items = [] #: Array[Llm::ClaudeBatchService::Item]
      skipped = [] #: Array[String]

      entries.each do |entry|
        external_id = entry.fetch("external_id")
        answer_type = entry.fetch("answer_type")
        unless schema_hash_for.key?(answer_type)
          skipped << "#{external_id}/#{answer_type}: no schema registered for answer_type #{answer_type.inspect}"
          next
        end

        bill = Bill.find_by(external_id: external_id)
        if bill.nil?
          skipped << "#{external_id}/#{answer_type}: no Bill in this database with that external_id"
          next
        end

        dump_dir = Legislation::Paths.prompt_dump_file(external_id, answer_type: answer_type, sway_locale: bill.sway_locale.name)
        system_file = dump_dir.join("#{answer_type}.system.txt")
        user_file = dump_dir.join("#{answer_type}.user.txt")
        unless system_file.exist? && user_file.exist?
          skipped << "#{external_id}/#{answer_type}: no dumped prompt at #{dump_dir} -- run `bundle exec rake sway:eval:dump` first"
          next
        end

        prompt = Llm::PromptPayload.new(system_prompt: system_file.read, user_message: user_file.read)
        items << Llm::ClaudeBatchService::Item.new(
          custom_id: Llm::BatchCustomId.build(external_id, answer_type),
          prompt: prompt,
          model: model,
          schema: schema_hash_for.fetch(answer_type),
          validation_schema: validation_schema_for.fetch(answer_type)
        )
      end

      if skipped.any?
        puts "skipped #{skipped.length} manifest entries:"
        skipped.each { |line| puts "  #{line}" }
      end

      if items.empty?
        abort "sway:llm:prove_batch: no items to submit -- every manifest entry (limit=#{limit}) was skipped, see above."
      end

      puts "model:                #{model}"
      puts "items:                #{items.length} (#{items.map(&:custom_id).join(", ")})"

      batch = Llm::ClaudeBatchService.submit(items: items)
      puts "batch id:             #{batch.id}"
      puts "expires at:           #{batch.expires_at}"

      poll_timeout_seconds = 600
      poll_interval_seconds = 10
      deadline = Time.current + poll_timeout_seconds
      started_at = Time.current
      status = batch

      # @lat: [[lat.md/explanation/llm-summaries#LLM bill summaries#Batch summarisation#What a batch can report while it runs]]
      report_counts = lambda do |snapshot|
        counts = snapshot.request_counts
        done = items.length - counts.processing.to_i
        percent = items.length.zero? ? 0 : (done * 100.0 / items.length).round
        puts "  [#{(Time.current - started_at).round}s] status=#{snapshot.processing_status} " \
          "processing=#{counts.processing} succeeded=#{counts.succeeded} errored=#{counts.errored} " \
          "canceled=#{counts.canceled} expired=#{counts.expired} -> #{percent}% not-processing"
      end

      puts "polling:"
      report_counts.call(status)
      until status.processing_status.to_s == "ended" || Time.current >= deadline
        sleep poll_interval_seconds
        status = Llm::ClaudeBatchService.status(batch_id: batch.id)
        report_counts.call(status)
      end

      unless status.processing_status.to_s == "ended"
        puts <<~MESSAGE
          batch #{batch.id} has not ended after #{poll_timeout_seconds}s of polling in this process --
          real batches can take up to 24 hours to complete. Check on it later with:

            Llm::ClaudeBatchService.status(batch_id: "#{batch.id}")
            Llm::ClaudeBatchService.results(batch_id: "#{batch.id}", items_by_custom_id: ...)
        MESSAGE
        exit 1
      end

      items_by_custom_id = items.index_by(&:custom_id)
      results = Llm::ClaudeBatchService.results(batch_id: batch.id, items_by_custom_id: items_by_custom_id)

      puts
      puts "results:"
      failure_count = 0
      total_input = 0
      total_output = 0
      total_cache_creation = 0
      total_cache_read = 0

      items.each do |item|
        result = results.fetch(item.custom_id)
        usage = result.usage

        if result.error
          failure_count += 1
          puts "  FAIL #{item.custom_id}: #{result.error.class.name.demodulize} #{result.error.message}"
          next
        end

        input_tokens = usage&.input_tokens.to_i
        output_tokens = usage&.output_tokens.to_i
        cache_creation = usage&.cache_creation_input_tokens.to_i
        cache_read = usage&.cache_read_input_tokens.to_i
        total_input += input_tokens
        total_output += output_tokens
        total_cache_creation += cache_creation
        total_cache_read += cache_read

        puts "  OK   #{item.custom_id}: input=#{input_tokens} output=#{output_tokens} " \
          "cache_creation=#{cache_creation} cache_read=#{cache_read}"
      end

      puts
      puts "totals: input=#{total_input} output=#{total_output} " \
        "cache_creation=#{total_cache_creation} cache_read=#{total_cache_read}"

      puts
      if failure_count.positive?
        puts "FAILED: #{failure_count} of #{items.length} items failed"
        exit 1
      else
        puts "PASSED: all #{items.length} items succeeded and schema-validated"
      end
    end
  end
end
