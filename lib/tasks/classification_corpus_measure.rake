# frozen_string_literal: true

# @lat: [[testimony-attachment-rules#Corpus measurement keeps jurisdiction identity]]
namespace :sway do
  namespace :measure do
    desc "Re-measure the corpus behind Testimony::ClassificationPromptBuilder's constants"
    task classification_corpus: :environment do
      markers = [
        /position:/i,
        /\b(?:in\s+)?(?:strong\s+)?(?:support|opposition|opposed|favorable|unfavorable)\b/i,
        /\bmemorandum\b/i,
        /form and legal sufficiency/i,
        /findings of fact/i,
        /\brecommend(?:s|ation|ed)?\b/i,
        /\ban ordinance concerning\b/i,
        /\bbe it ordained\b/i,
        /\bfiscal (?:impact|note)\b/i
      ]

      root = Legislation::Paths.hearings
      unless root.exist?
        abort "no hearing artifacts at #{root} — run the fetch_hearings stage first. " \
          "LEGISLATION_ROOT (and LEGISLATION_HEARINGS_ROOT) decide where they land."
      end

      docs = {} #: Hash[[String, Integer], Hash[Symbol, untyped]]
      hearing_files = Dir[root.join("*", "*.json").to_s].sort
      hearing_files.each do |path|
        sway_locale = File.basename(File.dirname(path))
        data =
          begin
            JSON.parse(File.read(path))
          rescue JSON::ParserError
            next
          end
        next unless data.is_a?(::Hash)

        Array(data["attachments"]).each do |attachment|
          id = attachment["id"]
          next unless id.is_a?(Integer)
          key = [sway_locale, id]
          next if docs.key?(key)

          docs[key] = {sway_locale: sway_locale, bill: File.basename(path, ".json"), name: attachment["name"].to_s}
        end
      end

      if docs.empty?
        abort "read #{hearing_files.length} #{"artifact".pluralize(hearing_files.length)} under #{root} " \
          "and found no attachments — nothing to measure. " \
          "The fetch_hearings stage has to have run AND found attachments."
      end

      classified_by_model = Testimony::AttachmentClassifier::MODEL_PASS_LABELS

      names = docs.values.map { |doc| [doc[:sway_locale], doc[:name]] }.uniq
      model_docs = docs.select { |_, doc| classified_by_model.include?(Testimony::NameRules.classify(doc[:name], sway_locale: doc[:sway_locale])) }
      model_names = model_docs.values.map { |doc| [doc[:sway_locale], doc[:name]] }.uniq
      tally = Hash.new(0) #: Hash[Symbol, Integer]
      names.each { |sway_locale, name| tally[Testimony::NameRules.classify(name, sway_locale: sway_locale)] += 1 }
      model_split = Hash.new(0) #: Hash[Symbol, Integer]
      model_docs.each_value { |doc| model_split[Testimony::NameRules.classify(doc[:name], sway_locale: doc[:sway_locale])] += 1 }

      puts "hearing artifacts read:    #{hearing_files.length}"
      puts "attachments (locale/id):   #{docs.length}"
      puts "distinct locale/names:     #{names.length}"
      puts "name-rule labels:          #{tally.sort.to_h.inspect}"
      puts "locale/names to the model: #{model_names.length}"
      puts "docs sent to the model:    #{model_docs.length} #{model_split.sort.to_h.inspect}"
      per_bill = model_docs.values.group_by { |doc| [doc[:sway_locale], doc[:bill]] }.transform_values(&:length)
      puts "per-bill model docs:       #{per_bill.values.sort.inspect} " \
        "(#{per_bill.length} #{"bill".pluralize(per_bill.length)})"

      attachment_sidecar = ->(sway_locale, id, extension) {
        path = Legislation::Paths.attachments.join(sway_locale, "attachment-#{id}.#{extension}")
        path if path.file?
      }

      lengths = {} #: Hash[[String, Integer], Integer]
      offsets = {} #: Hash[[String, Integer], Integer]
      unreadable = [] #: Array[[String, Integer]]
      no_marker = [] #: Array[[String, Integer]]
      model_docs.each_key do |key|
        sway_locale, id = key
        sidecar = attachment_sidecar.call(sway_locale, id, "txt")
        text =
          if sidecar
            sidecar.read
          else
            pdf = attachment_sidecar.call(sway_locale, id, "pdf")
            begin
              pdf ? TestimonyTextExtractor.new(pdf.to_s).call : nil
            rescue TestimonyTextExtractor::ExtractionFailed
              nil
            end
          end

        collapsed = Llm::PromptLabel.collapse(text)
        if collapsed.strip.empty?
          unreadable << key
          next
        end

        lengths[key] = collapsed.length
        offset = markers.filter_map { |marker| collapsed =~ marker }.min
        offset.nil? ? no_marker << key : offsets[key] = offset
      end

      sorted_lengths = lengths.values.sort
      puts
      puts "with readable text:        #{lengths.length}"
      puts "unreadable (no text):      #{unreadable.length} #{unreadable.sort.inspect}"
      if sorted_lengths.any?
        puts "collapsed length:          min #{sorted_lengths.first}, " \
          "median #{sorted_lengths[sorted_lengths.length / 2]}, max #{sorted_lengths.last}"
      end
      puts "no marker found:           #{no_marker.length} #{no_marker.sort.inspect}"
      if offsets.any?
        sorted_offsets = offsets.values.sort
        past_bound = offsets.count { |_, o| o >= Testimony::ClassificationPromptBuilder::MAX_DOCUMENT_CHARS }
        p90_index = [(sorted_offsets.length * 9).ceildiv(10) - 1, 0].max
        puts "first-marker offset:       worst #{sorted_offsets.last}, " \
          "p90 #{sorted_offsets[p90_index]}"
        puts "markers past the #{Testimony::ClassificationPromptBuilder::MAX_DOCUMENT_CHARS}-char bound: #{past_bound}"
      end
      sent_whole = lengths.count { |_, l| l <= Testimony::ClassificationPromptBuilder::MAX_DOCUMENT_CHARS }
      puts "sent in full at the bound: #{sent_whole} of #{lengths.length}"
    end
  end
end
