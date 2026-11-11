# frozen_string_literal: true

# @lat: [[eval-prompt-manifest-normalisation#Why sway:eval tasks stay thin over Eval:: services]]
namespace :sway do
  namespace :eval do
    desc "Dump every reference-set bill's prompt bytes for its answer types and commit their hashes to eval/manifest.json"
    task dump: :environment do
      begin
        Eval::PromptDump.assert_non_development_caps!
      rescue Eval::PromptDump::DevelopmentCapsError => e
        abort e.message
      end

      set_path = Rails.root.join("eval", "reference-set.json")
      unless set_path.exist?
        abort "eval/reference-set.json not found -- run `bundle exec rake sway:eval:reference_set` first. " \
          "The dump reads its bills and their answer types from that committed file; it does not choose its own."
      end

      picks = JSON.parse(set_path.read).reject { |row| row["kind"] == "header" }
      if picks.empty?
        abort "eval/reference-set.json holds a header and no picks -- nothing to dump."
      end

      entries = {} #: Hash[String, Hash[String, untyped]]
      failures = [] #: Array[String]

      # @lat: [[eval-prompt-manifest-normalisation#Why sway:eval tasks stay thin over Eval:: services]]
      picks.each do |pick|
        external_id = pick.fetch("external_id")
        matches = Bill.where(external_id: external_id).to_a
        if matches.length != 1
          failures << "#{external_id}: #{matches.length} bills in this database carry that external_id (want exactly 1)"
          next
        end
        bill = matches.fetch(0)

        pick.fetch("answer_types").each do |answer_type|
          entries["#{external_id}/#{answer_type}"] = Eval::PromptDump.call(bill: bill, answer_type: answer_type)
        rescue Eval::PromptDump::MissingDiffMarkdownError, Eval::PromptDump::MissingSourceError => e
          failures << "#{external_id}/#{answer_type}: #{e.class.name.demodulize}"
        end
      end

      if failures.any?
        abort <<~MESSAGE
          refusing to write a partial manifest -- #{failures.length} of the reference set's
          bill-and-answer-type pairs could not be dumped:

          #{failures.map { |line| "  #{line}" }.join("\n")}

          The summary answer type reads its source from an on-disk diff markdown file and
          never falls back to a bill's extracted text, because a dump built on the
          fallback compares two prompts rather than two models. LEGISLATION_DIFFS_ROOT
          decides where those files live (it falls back to LEGISLATION_ROOT/diffs).
          Generate the missing diffs and re-run.
        MESSAGE
      end

      manifest_path = Rails.root.join("eval", "manifest.json")
      manifest = manifest_path.exist? ? JSON.parse(manifest_path.read) : {}
      manifest_path.write(JSON.pretty_generate(manifest.merge(entries).sort.to_h))

      by_answer_type = entries.values.group_by { |entry| entry.fetch("answer_type") }
      total_bytes = entries.values.sum { |entry|
        entry.fetch("system_prompt_bytes") + entry.fetch("user_message_bytes")
      }

      puts "bills in the reference set:  #{picks.length}"
      puts "pairs dumped:                #{entries.length}"
      by_answer_type.keys.sort.each do |answer_type|
        puts "  %-26s %d" % ["#{answer_type}:", by_answer_type.fetch(answer_type).length]
      end
      puts "bytes written (untracked):   #{total_bytes}"
      puts "dump root:                   #{Legislation::Paths.prompt_dumps}"
      puts "builder_content_digest:      #{Eval::PromptDump.builder_content_digest}"
      puts "manifest entries written:    #{manifest_path}"

      Eval::ManifestStaleness.call(manifest_path: manifest_path)
      puts "staleness check:             passed against the freshly written manifest"
    end

    desc "Score every committed answer/verdict pair and write eval/REPORT.md"
    task score: :environment do
      manifest_path = Rails.root.join("eval", "manifest.json")
      unless manifest_path.exist?
        abort "eval/manifest.json not found -- run `bundle exec rake sway:eval:dump` first."
      end
      manifest = JSON.parse(manifest_path.read)

      answers = Eval::ScoreReport.load_fixtures(Rails.root.join("eval", "answers"))
      verdicts = Eval::ScoreReport.load_fixtures(Rails.root.join("eval", "verdicts"))

      if answers.empty? || verdicts.empty?
        abort "no committed fixtures found under eval/answers (#{answers.size}) or eval/verdicts (#{verdicts.size}) -- " \
          "run the dump, produce a candidate answer, and author a verdict before scoring."
      end

      result = Eval::ScoreReport.call(manifest: manifest, answers: answers, verdicts: verdicts, references: [])

      report_path = Rails.root.join("eval", "REPORT.md")
      report_path.write(result.to_markdown)
      puts result.to_markdown
      puts "report written:            #{report_path}"
    end

    desc "Choose the 30-bill reference set from the local corpus and commit the tally beside it"
    task reference_set: :environment do
      # @lat: [[eval-prompt-manifest-normalisation#Why the caps are asserted and recorded]]
      non_development_testimony_chars = 150_000
      non_development_source_chars = 300_000
      effective_testimony_chars = BillPositionsPromptBuilder.max_testimony_chars
      effective_source_chars = BillSummaryPromptBuilder.max_source_chars

      if effective_testimony_chars != non_development_testimony_chars || effective_source_chars != non_development_source_chars
        abort <<~MESSAGE
          refusing to measure the reference set under development-sized LLM prompt caps.
            effective testimony cap: #{effective_testimony_chars} (want #{non_development_testimony_chars})
            effective source cap:    #{effective_source_chars} (want #{non_development_source_chars})

          `dip run bundle exec rake` runs RAILS_ENV=development by default, where three
          of the four LLM prompt caps default smaller than everywhere else. An ENV
          prefix in front of `dip run` is DROPPED -- dip only forwards a host variable
          into the container when dip.yml names it (see project_dip_command_traps) --
          so exporting these on the command line ahead of `dip run` will not reach this
          process. Pass them as trailing NAME=VALUE arguments to the rake invocation
          itself instead; Rake reads those directly from its own argv:

            dip run bundle exec rake sway:eval:reference_set \\
              LLM_MAX_SOURCE_CHARS=300000 LLM_MAX_TESTIMONY_TOKENS=90000 \\
              LLM_MAX_TESTIMONY_CHARS=150000 LLM_MAX_SUMMARY_CONTEXT_CHARS=4000
        MESSAGE
      end

      set_path = Rails.root.join("eval", "reference-set.json")
      previous_header =
        if set_path.exist?
          JSON.parse(set_path.read, symbolize_names: true).find { |row| row.key?(:kind) && row[:kind] == "header" }
        end
      manual_substitutions = previous_header&.fetch(:manual_substitutions, []) || []

      result =
        begin
          Eval::ReferenceSetSelector.call(manual_substitutions: manual_substitutions)
        rescue Eval::ReferenceSetSelector::BandCollisionError,
          Eval::ReferenceSetSelector::InsufficientNoTestimonyError,
          Eval::ReferenceSetSelector::InvalidSubstitutionError,
          Eval::ReferenceSetSelector::MissingDiffMarkdownError => e
          abort "#{e.class.name.demodulize}: #{e.message}"
        end

      lines = []
      lines << "corpus bills with testimony (local corpus, by band): #{result.bands.values.sum}"
      lines << "excluded for missing diff markdown:                  #{result.excluded_for_missing_diff.length}"
      lines << ""
      lines << "band tally:"
      result.bands.each { |band, count| lines << "  %-14s %d" % [band, count] }
      lines << ""
      lines << "effective truncation boundary: #{effective_testimony_chars} chars " \
        "(BillPositionsPromptBuilder.max_testimony_chars)"
      lines << ""
      lines << "chosen ids, grouped by band (testimony-scored, 24):"
      Eval::ReferenceSetSelector::BANDS.each do |band|
        picks_in_band = result.picks.select { |pick| pick[:band] == band }
        next if picks_in_band.empty?

        lines << "  #{band}:"
        picks_in_band.each do |pick|
          note = pick[:substituted_for] ? " (substituted for #{pick[:substituted_for]})" : ""
          lines << "    #{pick[:external_id]} (#{pick[:testimony_chars]} chars)#{note}"
        end
      end
      lines << ""
      lines << "chosen ids, no-testimony (summary answer type only, 6):"
      result.no_testimony_picks.each { |pick| lines << "  #{pick[:external_id]}" }
      lines << ""
      lines << "-- the selection above stratifies on testimony length, which drives the"
      lines << "   POSITIONS answer. The summary answer's source is on-disk diff markdown,"
      lines << "   capped separately -- the table below shows what the testimony-length"
      lines << "   stratification does and does not cover for the SUMMARY answer type."
      lines << "source-character band tally (over the chosen 30, summary source cap " \
        "#{effective_source_chars} chars, BillSummaryPromptBuilder.max_source_chars):"
      result.source_char_bands.each { |band, count| lines << "  %-16s %d" % [band, count] }

      report_text = "#{lines.join("\n")}\n"
      print report_text

      set_txt_path = Rails.root.join("eval", "reference-set.txt")
      set_txt_path.write(report_text)

      picks_json = (result.picks + result.no_testimony_picks).map do |pick|
        {
          external_id: pick[:external_id],
          band: pick[:band].to_s,
          extracted_testimony_chars: pick[:testimony_chars],
          answer_types: (pick[:band] == :no_testimony) ? ["summary"] : %w[summary positions],
          substituted_for: pick[:substituted_for]
        }
      end
      source_chars_by_id = {} #: Hash[String, Integer]
      (result.picks + result.no_testimony_picks).each do |pick|
        path = Legislation::Paths.diff_markdown_file(pick[:external_id], sway_locale: pick[:sway_locale])
        source_chars_by_id[pick[:external_id]] = path.read.length
      end
      picks_json.each do |row|
        chars = source_chars_by_id.fetch(row.fetch(:external_id))
        row[:source_chars] = chars
        row[:source_char_band] = (chars >= effective_source_chars) ? "over_source_cap" : "under_source_cap"
      end

      header = {
        kind: "header",
        run_at: Time.current.utc.iso8601,
        effective_truncation_boundary: effective_testimony_chars,
        summary_source_cap: effective_source_chars,
        source_char_bands: result.source_char_bands,
        manual_substitutions: manual_substitutions
      }

      set_path.write(JSON.pretty_generate([header] + picks_json))

      puts
      puts "reference set written:     #{set_path}"
      puts "tally committed:           #{set_txt_path}"
    end
  end
end
