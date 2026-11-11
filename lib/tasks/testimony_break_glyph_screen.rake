# frozen_string_literal: true

# @lat: [[testimony-attachment-rules#Testimony attachment rules#Why the break-glyph screen is a task rather than a note]]
# @lat: [[testimony-character-repair-break-glyphs#The glyphs, and how each was found]]
namespace :sway do
  namespace :measure do
    desc "Score every character sitting between two ASCII letters in a bill's testimony as damage or ordinary text"
    task :break_glyphs, [:external_id] => :environment do |_task, args|
      external_id = args[:external_id].presence || abort("usage: rake sway:measure:break_glyphs[<bill external_id>]")

      bill = Bill.find_by(external_id: external_id) || abort("no bill with external_id #{external_id}")
      raw = bill.bill_llm_provisioning&.extracted_testimony.to_s
      abort("bill #{external_id} has no extracted testimony -- run the fetch-hearings stage first") if raw.empty?

      pairs = Testimony::CharacterRepair::CANDIDATE_PAIRS
      vocabulary = Testimony::CharacterRepair::SEED_VOCABULARY | raw.scan(/[A-Za-z]+/).to_set

      # @lat: [[testimony-character-repair-break-glyphs#Stop finding these one at a time]]
      candidates = raw.each_char.each_cons(3).filter_map { |before, char, after|
        next unless before.ord < 128 && after.ord < 128
        next unless before.match?(/[A-Za-z]/) && after.match?(/[A-Za-z]/)
        next if char.match?(/[A-Za-z]/)

        char
      }.tally

      rows = candidates.keys.map { |glyph|
        runs = raw.scan(/[A-Za-z]+(?:#{Regexp.escape(glyph)}[A-Za-z]+)+/)
        resolved = runs.map { |run|
          pairs.select { |pair| vocabulary.include?(run.gsub(glyph, pair)) }.uniq
        }
        corroborated = resolved.count { |matches| matches.length == 1 }

        {
          codepoint: format("U+%04X", glyph.ord),
          printable: glyph.ord.between?(33, 126) ? glyph : "",
          known: Testimony::CharacterRepair::BREAK_GLYPHS.include?(glyph),
          runs: runs.length,
          corroborated: corroborated,
          rate: runs.empty? ? 0.0 : (corroborated.to_f / runs.length * 100).round(1),
          pairs: resolved.select { |matches| matches.length == 1 }.flatten.tally.sort_by { |_, count| -count }.first(3)
        }
      }.sort_by { |row| -row[:rate] }

      puts "bill #{external_id}: #{raw.length} characters of extracted testimony"
      puts "codepoint chr  known      runs  corroborated   rate%  resolves to"
      rows.each do |row|
        puts format(
          "%-9s %-4s %-6s %8d %13d %6s%%  %s",
          row[:codepoint], row[:printable], row[:known] ? "yes" : "-",
          row[:runs], row[:corroborated], row[:rate],
          row[:pairs].map { |pair, count| "#{pair}=#{count}" }.join(" ")
        )
      end

      # @lat: [[testimony-character-repair-break-glyphs#Stop finding these one at a time#Running the screen again]]
      min_runs = 5
      missed = rows.select { |row| !row[:known] && row[:rate] >= 50.0 && row[:runs] >= min_runs }
      if missed.any?
        puts
        puts "LIKELY BREAK GLYPHS NOT IN BREAK_GLYPHS (at least #{min_runs} runs): #{missed.pluck(:codepoint).join(", ")}"
      end
    end
  end
end
