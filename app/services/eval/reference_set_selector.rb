# frozen_string_literal: true

module Eval
  # @lat: [[lat.md/explanation/eval-reference-set-selection#Why the bands are taken whole rather than sampled]]
  class ReferenceSetSelector
    # @lat: [[lat.md/explanation/eval-reference-set-selection#Why the bands are taken whole rather than sampled]]
    class BandCollisionError < StandardError; end

    # @lat: [[lat.md/explanation/eval-reference-set-selection#How ReferenceSetSelector defines its band thresholds and exclusions]]
    class InsufficientNoTestimonyError < StandardError; end

    # @lat: [[lat.md/explanation/eval-reference-set-selection#How ReferenceSetSelector defines its band thresholds and exclusions]]
    class InvalidSubstitutionError < StandardError; end

    # @lat: [[lat.md/explanation/eval-reference-set-selection#How ReferenceSetSelector defines its band thresholds and exclusions]]
    class MissingDiffMarkdownError < StandardError; end

    SET_SIZE = 30
    TESTIMONY_SCORED_SLOTS = 24
    NO_TESTIMONY_SLOTS = 6

    # @lat: [[lat.md/explanation/eval-reference-set-selection#Why the truncation boundary is a method call, not a constant]]
    CONTROL_BAND_LOWER = 50_000
    BULK_10K_50K_LOWER = 10_000
    BULK_1K_10K_LOWER = 1_000

    BANDS = %i[truncation control bulk_10k_50k bulk_1k_10k bulk_under_1k].freeze

    # @lat: [[lat.md/explanation/eval-reference-set-selection#Why the bands are taken whole rather than sampled]]
    BULK_BAND_ORDER = %i[bulk_10k_50k bulk_1k_10k bulk_under_1k].freeze

    # @lat: [[lat.md/explanation/eval-reference-set-selection#How ReferenceSetSelector defines its band thresholds and exclusions]]
    SOURCE_CHAR_BANDS = %i[over_source_cap under_source_cap].freeze

    class Result < Data.define(
      :bands, :source_char_bands, :picks, :no_testimony_picks,
      :excluded_for_missing_diff, :substitutions_applied
    )
    end

    class << self
      def call(manual_substitutions: [])
        new(manual_substitutions: manual_substitutions).call
      end

      # @lat: [[lat.md/explanation/eval-reference-set-selection#Why the truncation boundary is a method call, not a constant]]
      def truncation_cap
        BillPositionsPromptBuilder.max_testimony_chars
      end

      # @lat: [[lat.md/explanation/eval-reference-set-selection#Why the truncation boundary is a method call, not a constant]]
      def source_cap
        BillSummaryPromptBuilder.max_source_chars
      end
    end

    def initialize(manual_substitutions: [])
      @manual_substitutions = manual_substitutions
      @substitutions_applied = []
    end

    def call
      corpus = load_corpus
      corpus_by_id = corpus.index_by { |pick| pick[:external_id] }

      with_testimony, no_testimony = corpus.partition { |pick| pick[:testimony_chars].positive? }
      banded = band_corpus(with_testimony)
      band_counts = BANDS.to_h { |name| [name, banded.fetch(name).length] }

      whole_picks = sort_band(banded.fetch(:truncation)) + sort_band(banded.fetch(:control))
      if whole_picks.length >= TESTIMONY_SCORED_SLOTS
        raise BandCollisionError, collision_message(band_counts, whole_picks.length)
      end

      testimony_picks = whole_picks + bulk_fill(banded, TESTIMONY_SCORED_SLOTS - whole_picks.length)

      no_testimony_pool = sort_band(no_testimony)
      if no_testimony_pool.length < NO_TESTIMONY_SLOTS
        raise InsufficientNoTestimonyError,
          "found #{no_testimony_pool.length} bills carrying a summary source but no testimony -- " \
          "need #{NO_TESTIMONY_SLOTS}. Widen the corpus (a fuller local pipeline re-run) rather than lowering this count."
      end
      no_testimony_picks = no_testimony_pool.first(NO_TESTIMONY_SLOTS).map { |pick| pick.merge(band: :no_testimony) }

      testimony_picks = apply_substitutions(testimony_picks, corpus_by_id)

      excluded = missing_diff_ids(testimony_picks + no_testimony_picks)
      if excluded.any?
        raise MissingDiffMarkdownError,
          "#{excluded.length} chosen #{(excluded.length == 1) ? "bill has" : "bills have"} no diff markdown on this machine: " \
          "#{excluded.sort.join(", ")}. LEGISLATION_DIFFS_ROOT (or LEGISLATION_ROOT) decides where those files live -- " \
          "run the local pipeline's diff-generation stage for them first. This never falls back to extracted text."
      end

      Result.new(
        bands: band_counts,
        source_char_bands: source_char_bands_for(testimony_picks + no_testimony_picks),
        picks: testimony_picks,
        no_testimony_picks: no_testimony_picks,
        excluded_for_missing_diff: excluded,
        substitutions_applied: @substitutions_applied
      )
    end

    private

    attr_reader :manual_substitutions

    # @lat: [[eval-corpus-is-local-not-production#What the corpus is]]
    def load_corpus
      Bill.joins(:bill_llm_provisioning)
        .includes(:sway_locale)
        .where.not(bill_llm_provisioning: {diff_content: [nil, ""]})
        .map do |bill|
          {
            external_id: bill.external_id,
            sway_locale: bill.sway_locale.name,
            testimony_chars: bill.bill_llm_provisioning.extracted_testimony.to_s.length
          }
        end
    end

    def band_corpus(items)
      banded = BANDS.to_h { |name| [name, []] }
      items.each do |item|
        name = band_for(item[:testimony_chars])
        banded[name] << item.merge(band: name)
      end
      banded
    end

    def band_for(chars)
      cap = self.class.truncation_cap
      return :truncation if chars > cap
      return :control if chars >= CONTROL_BAND_LOWER
      return :bulk_10k_50k if chars >= BULK_10K_50K_LOWER
      return :bulk_1k_10k if chars >= BULK_1K_10K_LOWER

      :bulk_under_1k
    end

    # @lat: [[lat.md/explanation/eval-reference-set-selection#How ReferenceSetSelector defines its band thresholds and exclusions]]
    def sort_band(items)
      items.sort_by { |item| [-item[:testimony_chars], item[:external_id]] }
    end

    def bulk_fill(banded, remainder)
      picks = []
      BULK_BAND_ORDER.each do |name|
        next if remainder <= 0

        taken = sort_band(banded.fetch(name)).first(remainder)
        picks.concat(taken)
        remainder -= taken.length
      end
      picks
    end

    def collision_message(band_counts, whole_count)
      "the truncation and control bands together hold #{whole_count} bills -- " \
        "at or past the #{TESTIMONY_SCORED_SLOTS} testimony-scored slots the set has room for. " \
        "Band tally: #{band_counts.sort.to_h.inspect}. Both bands are taken whole by owner decision, " \
        "and the set stays at #{SET_SIZE} by owner decision -- only a person can say which one gives. " \
        "This selector will not silently sample a band the design says to take whole."
    end

    def apply_substitutions(picks, corpus_by_id)
      picks = picks.dup
      applied = []
      manual_substitutions.each do |substitution|
        from_id = substitution.fetch(:from).to_s
        to_id = substitution.fetch(:to).to_s

        found_index = picks.index { |pick| pick[:external_id] == from_id && pick[:band] == :bulk_10k_50k }
        if found_index.nil?
          raise InvalidSubstitutionError,
            "manual_substitutions names #{from_id.inspect} to replace, but it is not a current pick in the " \
            "10k-50k band. A substitution only ever replaces a pick in that band, never adds to the set."
        end
        index = found_index #: Integer

        replacement = corpus_by_id.fetch(to_id, nil)
        if replacement.nil?
          raise InvalidSubstitutionError,
            "manual_substitutions names #{to_id.inspect} as the replacement for #{from_id.inspect}, but no bill " \
            "with that external_id carries a summary source in this corpus."
        end
        found_pick = replacement #: pick

        updated_pick = found_pick.merge(band: :bulk_10k_50k, substituted_for: from_id) #: pick
        picks[index] = updated_pick
        applied << {from: from_id, to: to_id}
      end
      @substitutions_applied = applied
      picks
    end

    def missing_diff_ids(picks)
      picks.filter_map do |pick|
        path = Legislation::Paths.diff_markdown_file(pick[:external_id], sway_locale: pick[:sway_locale])
        pick[:external_id] unless path.exist?
      end
    end

    def source_char_bands_for(picks)
      counts = SOURCE_CHAR_BANDS.to_h { |name| [name, 0] }
      cap = self.class.source_cap
      picks.each do |pick|
        path = Legislation::Paths.diff_markdown_file(pick[:external_id], sway_locale: pick[:sway_locale])
        chars = path.read.length
        counts[(chars >= cap) ? :over_source_cap : :under_source_cap] += 1
      end
      counts
    end
  end
end
