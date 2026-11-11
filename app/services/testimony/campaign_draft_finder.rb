# frozen_string_literal: true

module Testimony
  # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why drafts are matched on lines and on word shingles]]
  # @lat: [[campaign-draft-shingle-matching#Why the draft id folds in both grains]]
  class CampaignDraftFinder
    # @lat: [[campaign-draft-shingle-matching#Why line candidates count alphabetic characters and require two letters]]
    MIN_PHRASE_CHARS = 25

    # @lat: [[campaign-draft-shingle-matching#Why 8 words, not fewer]]
    SHINGLE_WINDOW_WORDS = 8

    # @lat: [[campaign-draft-shingle-matching#Why line candidates count alphabetic characters and require two letters]]
    MIN_LETTERS_FOR_REUSE = 2

    CAMPAIGN_DRAFT_ID_LENGTH = 16

    Result = Data.define(:letters, :campaign_drafts)

    class << self
      def call(text:, letters:)
        new(text: text, letters: letters).call
      end
    end

    def initialize(text:, letters:)
      @text = text.to_s
      @letters = letters
    end

    def call
      letter_paragraphs = @letters.map { |letter| paragraphs_for(letter) }

      phrase_occurrences = collect_phrase_occurrences(letter_paragraphs)
      reused_phrase_hashes = select_reused(phrase_occurrences)

      shingle_occurrences = collect_shingle_occurrences(letter_paragraphs)
      reused_shingle_hashes = select_reused(shingle_occurrences)

      parent = {}
      connect_shared_letters(letter_paragraphs, reused_phrase_hashes, reused_shingle_hashes, parent)

      drafts, campaign_draft_id_by_letter_index = build_drafts(letter_paragraphs, reused_phrase_hashes, reused_shingle_hashes, parent)
      augmented_letters = build_letters(letter_paragraphs, reused_phrase_hashes, campaign_draft_id_by_letter_index)

      Result.new(letters: augmented_letters, campaign_drafts: drafts)
    end

    private

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why the letter text was never a redaction question]]
    def letter_text(letter)
      offset = letter.fetch("character_offset").to_i
      length = letter.fetch("characters").to_i
      @text[offset, length].to_s
    end

    # @lat: [[extracted-text-phrase-matching#Stripping the mail envelope by field, not by block]]
    def paragraphs_for(letter)
      envelope_stripped = Testimony::ExtractedText.strip_envelope(letter_text(letter))
      Testimony::ExtractedText.strip_recipient_headers(envelope_stripped).split(/\n[ \t]*\n+/)
    end

    # @lat: [[campaign-letter-disclosure#Campaign letter disclosure#Why drafts are matched on lines and on word shingles]]
    def normalize(line)
      line.strip.gsub(/[ \t]+/, " ").downcase
    end

    # @lat: [[campaign-draft-shingle-matching#Why shingling is additive, never a replacement]]
    def flowing_words(paragraph)
      paragraph.gsub(/\s+/, " ").strip.downcase.split(" ")
    end

    def content_hash(normalized)
      Digest::SHA256.hexdigest(normalized)
    end

    def alpha_char_count(normalized)
      normalized.scan(/[[:alpha:]]/).length
    end

    def each_candidate_line(paragraph)
      paragraph.split("\n").each do |raw_line|
        normalized = normalize(raw_line)
        next if alpha_char_count(normalized) < MIN_PHRASE_CHARS

        yield(normalized, raw_line.strip)
      end
    end

    # @lat: [[campaign-draft-shingle-matching#Why 8 words, not fewer]]
    def each_candidate_shingle(paragraph)
      words = flowing_words(paragraph)
      return if words.length < SHINGLE_WINDOW_WORDS

      words.each_cons(SHINGLE_WINDOW_WORDS) { |window| yield window.join(" ") }
    end

    def collect_phrase_occurrences(letter_paragraphs)
      occurrences = Hash.new { |hash, key| hash[key] = [] }
      letter_paragraphs.each_with_index do |paragraphs, letter_index|
        paragraphs.each do |paragraph|
          each_candidate_line(paragraph) do |normalized, _original|
            occurrences[content_hash(normalized)] << letter_index
          end
        end
      end
      occurrences
    end

    def collect_shingle_occurrences(letter_paragraphs)
      occurrences = Hash.new { |hash, key| hash[key] = [] }
      letter_paragraphs.each_with_index do |paragraphs, letter_index|
        paragraphs.each do |paragraph|
          each_candidate_shingle(paragraph) do |shingle|
            occurrences[content_hash(shingle)] << letter_index
          end
        end
      end
      occurrences
    end

    def select_reused(occurrences)
      reused = {}
      occurrences.each do |hash, letter_indices|
        reused[hash] = true if letter_indices.uniq.length >= MIN_LETTERS_FOR_REUSE
      end
      reused
    end

    # @lat: [[campaign-draft-shingle-matching#Why shingling is additive, never a replacement]]
    def node!(parent, node)
      parent[node] ||= node
    end

    def find_root(parent, node)
      node!(parent, node)
      current = node
      current = parent.fetch(current) while parent.fetch(current) != current
      current
    end

    def union(parent, a, b)
      root_a = find_root(parent, a)
      root_b = find_root(parent, b)
      parent[root_a] = root_b unless root_a == root_b
    end

    def connect_shared_letters(letter_paragraphs, reused_phrase_hashes, reused_shingle_hashes, parent)
      letter_paragraphs.each_with_index do |paragraphs, letter_index|
        letter_node = "letter:#{letter_index}"
        paragraphs.each do |paragraph|
          each_candidate_line(paragraph) do |normalized, _original|
            hash = content_hash(normalized)
            next unless reused_phrase_hashes.key?(hash)

            union(parent, letter_node, "phrase:#{hash}")
          end

          each_candidate_shingle(paragraph) do |shingle|
            hash = content_hash(shingle)
            next unless reused_shingle_hashes.key?(hash)

            union(parent, letter_node, "shingle:#{hash}")
          end
        end
      end
    end

    def component_members(reused_hashes, prefix, parent)
      components = Hash.new { |hash, key| hash[key] = [] }
      reused_hashes.each_key do |hash|
        node = "#{prefix}#{hash}"
        next unless parent.key?(node)

        components[find_root(parent, node)] << hash
      end
      components
    end

    def build_drafts(letter_paragraphs, reused_phrase_hashes, reused_shingle_hashes, parent)
      letter_components = Hash.new { |hash, key| hash[key] = [] }
      letter_paragraphs.each_index do |letter_index|
        letter_node = "letter:#{letter_index}"
        next unless parent.key?(letter_node)

        letter_components[find_root(parent, letter_node)] << letter_index
      end

      phrase_components = component_members(reused_phrase_hashes, "phrase:", parent)
      shingle_components = component_members(reused_shingle_hashes, "shingle:", parent)

      drafts = []
      campaign_draft_id_by_letter_index = {}

      letter_components.each do |root, letter_indices|
        distinct_indices = letter_indices.uniq
        next if distinct_indices.length < MIN_LETTERS_FOR_REUSE

        # @lat: [[campaign-draft-shingle-matching#Why the draft id folds in both grains]]
        combined_hashes = (phrase_components[root] + shingle_components[root]).uniq.sort
        campaign_draft_id = Digest::SHA256.hexdigest(combined_hashes.join(","))[0, CAMPAIGN_DRAFT_ID_LENGTH]

        drafts << {
          "id" => campaign_draft_id,
          "letter_positions" => distinct_indices.sort.map { |index| @letters[index].fetch("position") }
        }

        distinct_indices.each { |index| campaign_draft_id_by_letter_index[index] = campaign_draft_id }
      end

      [drafts, campaign_draft_id_by_letter_index]
    end

    # @lat: [[campaign-draft-shingle-matching#Why added_words stays line-based]]
    def added_words_for(paragraphs, reused_phrase_hashes)
      kept_paragraphs = []
      paragraphs.each do |paragraph|
        kept_lines = []
        paragraph.split("\n").each do |raw_line|
          normalized = normalize(raw_line)
          reused = alpha_char_count(normalized) >= MIN_PHRASE_CHARS && reused_phrase_hashes.key?(content_hash(normalized))
          kept_lines << raw_line.strip unless reused
        end
        kept_paragraphs << kept_lines.join("\n") unless kept_lines.empty?
      end
      kept_paragraphs.join("\n\n")
    end

    def build_letters(letter_paragraphs, reused_phrase_hashes, campaign_draft_id_by_letter_index)
      @letters.each_with_index.map do |letter, index|
        letter.merge(
          "campaign_draft_id" => campaign_draft_id_by_letter_index[index],
          "added_words" => added_words_for(letter_paragraphs[index], reused_phrase_hashes)
        )
      end
    end
  end
end
