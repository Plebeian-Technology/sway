# frozen_string_literal: true

require "rails_helper"

# We used to attach the cache marker to EVERY system block, ignoring the
# model's minimum. On the default model (floor 4096), none of the four
# prompts is long enough, so it bought nothing.
RSpec.describe Llm::PromptCache do
  # The repo stated the same chars-per-token density as two different
  # numbers: 4.0 here, 3.5 in the cache gate. For any prefix in that gap,
  # we paid full price with no error and no failing test.
  describe "CHARS_PER_TOKEN" do
    it "is the single source of truth the R5 gate's Tier-2 heuristic reads" do
      expect(described_class::CHARS_PER_TOKEN).to eq(CachePrefixTokenizer::TIER_2_CHARS_PER_TOKEN)
    end

    it "matches the 3.5 chars/token density the R5 gate is written against" do
      expect(described_class::CHARS_PER_TOKEN).to eq(3.5)
    end

    # A worked example: 4000 characters against a model with a 1024 floor.
    it "calls the finding's near-threshold case cacheable, as the gate rule does" do
      expect(described_class.estimated_tokens("x" * 4000)).to eq(1142)
      expect(described_class.cacheable?("x" * 4000, model: "claude-sonnet-5-5")).to be(true)
    end
  end

  # Anthropic's published minimums. These sizes are picked against the
  # chars-per-token ESTIMATE this module uses, not a live tokenizer — the
  # module only promises an estimate.
  describe ".minimum_prefix_tokens" do
    it "returns 4096 for Haiku 5.5, including the dated model id operators actually select" do
      expect(described_class.minimum_prefix_tokens("claude-haiku-5-5")).to eq(4096)
    end

    it "returns 1024 for the Sonnet tier" do
      expect(described_class.minimum_prefix_tokens("claude-sonnet-4-6")).to eq(1024)
      expect(described_class.minimum_prefix_tokens("claude-sonnet-4-5")).to eq(1024)
      expect(described_class.minimum_prefix_tokens("claude-sonnet-5-5")).to eq(1024)
    end

    it "returns 512 for Opus 5.5" do
      expect(described_class.minimum_prefix_tokens("claude-opus-5-5")).to eq(512)
    end

    # Opus 4.8 stopped being selectable, but its row stayed: a missing
    # model counts as floor unknown, and #cacheable? attaches the marker
    # anyway on unknown. Deleting it would swap a fact for a guess.
    it "returns 1024 for Opus 4.8, a retired model whose confirmed floor is kept" do
      expect(described_class.minimum_prefix_tokens("claude-opus-4-8")).to eq(1024)
      expect(AdminSetting::SUPPORTED_MODELS).not_to include("claude-opus-4-8")
    end

    # A23-06: the retired rows are still reachable, despite an old comment
    # claiming otherwise. #resolve_model_for reads a PERSISTED admin
    # setting, so a retired value keeps returning.
    it "still answers for a retired model a persisted AdminSetting can hold" do
      AdminSetting.singleton.update_columns(summarization_model: "claude-sonnet-4-6")

      persisted = AdminSetting.singleton.summarization_model

      expect(persisted).to eq("claude-sonnet-4-6")
      expect(described_class.minimum_prefix_tokens(persisted)).to eq(1024)
    end

    it "covers every Claude model an operator can select" do
      AdminSetting::SUPPORTED_MODELS.select { |m| Llm::ModelCatalog.fetch(m).claude? }.each do |model|
        expect(described_class.minimum_prefix_tokens(model)).to be_a(Integer),
          "#{model} is selectable but has no documented floor — #cacheable? would fall through to attach-anyway"
      end
    end

    it "returns nil for a model whose floor is not documented here" do
      expect(described_class.minimum_prefix_tokens("claude-nonexistent-9")).to be_nil
    end

    # The lookup matches model names by PREFIX against a Hash, walked in
    # write order — the only thing keeping the answer right today. A
    # shorter name above a longer one gives the wrong floor.
    it "prefers the longest matching family, not the first one declared" do
      stub_const(
        "Llm::PromptCache::MINIMUM_CACHEABLE_PREFIX_TOKENS",
        {"claude-opus-4" => 4096, "claude-opus-4-8" => 1024}
      )

      expect(described_class.minimum_prefix_tokens("claude-opus-4-8-20260101")).to eq(1024)
    end

    it "still resolves a shorter family when no longer one matches" do
      stub_const(
        "Llm::PromptCache::MINIMUM_CACHEABLE_PREFIX_TOKENS",
        {"claude-opus-4" => 4096, "claude-opus-4-8" => 1024}
      )

      expect(described_class.minimum_prefix_tokens("claude-opus-4-6")).to eq(4096)
    end
  end

  describe ".cacheable?" do
    # These prefixes are READ OFF the prompt builders, not hard-coded
    # literals — past re-measurements went stale without a failing
    # assertion, since a literal can't disagree with itself.
    let(:summary_sized_prefix) { BillSummaryPromptBuilder.new(Bill.new, active_categories: []).system_prompt }
    let(:positions_sized_prefix) { BillPositionsPromptBuilder.new(Bill.new).system_prompt }
    let(:classifier_sized_prefix) { Testimony::ClassificationPromptBuilder.new([]).system_prompt }
    # The FOURTH structured call, and the one nothing measured: it routes
    # through the same system_block as the other three, so it can log a
    # withheld marker too — it just had no example before now.
    let(:categorize_sized_prefix) do
      BillCategoryPromptBuilder.new(
        Bill.new,
        active_categories: %w[Housing Health Economy Education Transit Safety].map { |n| Category.new(name: n) }
      ).payload.system_prompt
    end

    it "is false for the summary prefix on Haiku 5.5 — the operator default's floor is 4096" do
      expect(described_class.cacheable?(summary_sized_prefix, model: "claude-haiku-5-5")).to be(false)
    end

    it "is true for the summary prefix on Sonnet 5.5 — it clears the 1024 floor" do
      expect(described_class.cacheable?(summary_sized_prefix, model: "claude-sonnet-5-5")).to be(true)
    end

    # @lat: [[untrusted-text-in-prompts#What a cacheable prefix needs]]
    it "is true for the positions prefix on both models an operator can pick above Haiku" do
      %w[claude-sonnet-5-5 claude-opus-5-5].each do |model|
        expect(described_class.cacheable?(positions_sized_prefix, model: model)).to be(true)
      end
    end

    it "is false for the positions prefix on Haiku 5.5" do
      expect(described_class.cacheable?(positions_sized_prefix, model: "claude-haiku-5-5")).to be(false)
    end

    # @lat: [[untrusted-text-in-prompts#What a cacheable prefix needs]]
    it "is true for the classifier prefix on both models an operator can pick above Haiku" do
      %w[claude-sonnet-5-5 claude-opus-5-5].each do |model|
        expect(described_class.cacheable?(classifier_sized_prefix, model: model)).to be(true)
      end
    end

    # Still short of the DEFAULT model's floor, and that is the number that
    # decides what actually happens on a production classification call.
    it "is false for the classifier prefix on Haiku 5.5" do
      expect(described_class.cacheable?(classifier_sized_prefix, model: "claude-haiku-5-5")).to be(false)
    end

    it "is true for the summary prefix on Opus 5.5 — it clears its 512 floor" do
      expect(described_class.cacheable?(summary_sized_prefix, model: "claude-opus-5-5")).to be(true)
    end

    it "is false for an undocumented model and logs a warning" do
      expect(SwayLogging).to receive(:warn).with("llm.prompt_cache.unknown_model", model: "claude-nonexistent-9")
      expect(described_class.cacheable?(classifier_sized_prefix, model: "claude-nonexistent-9")).to be(false)
    end

    # THE GUARD THE FLOOR CHECKS COULD NOT BE: a hand-measured figure
    # written into a comment rots, since a floor check only fires when a
    # prefix CROSSES a floor. These examples ASSERT a band instead.
    it "keeps the summary prefix the size this file pins it at (~3068 tokens)" do
      actual = described_class.estimated_tokens(summary_sized_prefix)

      expect(actual).to be_within(101).of(3068),
        "summary prefix is now #{actual} estimated tokens, not ~3068. Re-measure and " \
        "update it here; this example is what asserts it."
    end

    # A19-15: moved from ~1111 when the output contract started stating
    # the bounds config/schemas/bill_positions.json checks against. This
    # example noticed, printing the new figure on failure.
    #
    # Moved again, from ~1222 to ~1377, when
    # #header gained the paragraph explaining the two per-letter kind-of-
    # source headings (INDIVIDUAL_LETTER_HEADING / NAMEABLE_LETTER_HEADING).
    # Fixed, bill-independent text, so it stays in the cacheable prefix —
    # this example is what proves that, by noticing the size move.
    it "keeps the positions prefix the size this file pins it at (~2743 tokens)" do
      actual = described_class.estimated_tokens(positions_sized_prefix)

      expect(actual).to be_within(69).of(2743),
        "positions prefix is now #{actual} estimated tokens, not ~2743. Re-measure and " \
        "update it here; this example is what asserts it."
    end

    # Far below every documented floor and near-miss band, so nothing is
    # withheld or warned about. Pinned so a prefix growing by ~180
    # characters starts failing here instead of silently.
    it "is false for the categorize prefix on every documented model" do
      %w[claude-haiku-5-5 claude-sonnet-5 claude-opus-5-5].each do |model|
        expect(described_class.cacheable?(categorize_sized_prefix, model: model)).to be(false)
      end
    end

    it "keeps the categorize prefix the size this file pins it at (~327 tokens)" do
      actual = described_class.estimated_tokens(categorize_sized_prefix)

      expect(actual).to be_within(17).of(327),
        "categorize prefix is now #{actual} estimated tokens, not ~327. Re-measure and " \
        "update it here; this example is what asserts it."
    end

    it "keeps the classifier prefix the size this file pins it at (~1095 tokens)" do
      actual = described_class.estimated_tokens(classifier_sized_prefix)

      expect(actual).to be_within(55).of(1095),
        "classifier prefix is now #{actual} estimated tokens, not ~1095. Re-measure and " \
        "update it here; this example is what asserts it."
    end

    it "is false for a blank prefix on a documented model" do
      expect(described_class.cacheable?("", model: "claude-sonnet-5-5")).to be(false)
      expect(described_class.cacheable?(nil, model: "claude-sonnet-5-5")).to be(false)
    end
  end

  describe ".cache_control_for" do
    # Read off the builders, like the .cacheable? lets above. These two examples
    # are about the REAL summary prefix, so a literal standing in for it could
    # only go stale.
    let(:summary_sized_prefix) { BillSummaryPromptBuilder.new(Bill.new, active_categories: []).system_prompt }
    let(:classifier_sized_prefix) { Testimony::ClassificationPromptBuilder.new([]).system_prompt }

    it "returns the ephemeral marker when the prefix can cache" do
      expect(described_class.cache_control_for(summary_sized_prefix, model: "claude-sonnet-5-5"))
        .to eq({type: "ephemeral"})
    end

    it "returns nil when the prefix cannot clear the model's floor" do
      expect(described_class.cache_control_for(summary_sized_prefix, model: "claude-haiku-5-5")).to be_nil
    end

    # Withholding the marker is the decision that costs money, and it was
    # the one decision nothing wrote down. A prefix missing the floor by a
    # few tokens now says so, with the numbers that decided it.
    it "logs the withholding with the estimate and the floor that produced it" do
      expect(SwayLogging).to receive(:warn).with(
        "llm.prompt_cache.withheld",
        hash_including(model: "claude-haiku-5-5", estimated_tokens: 3428, minimum_prefix_tokens: 4096)
      )

      described_class.cache_control_for("x" * 12000, model: "claude-haiku-5-5")
    end

    # A23-02: the log line meant to catch a near-miss, but both prefixes
    # miss the default floor by a wide margin, so it warned on EVERY call.
    # Sizes are gone from prose; band examples ASSERT them now.
    it "does not log a prefix that is structurally far below the floor" do
      expect(SwayLogging).not_to receive(:warn)

      described_class.cache_control_for(classifier_sized_prefix, model: "claude-haiku-5-5")
    end

    it "still withholds the marker for that prefix — only the LOG is quieter" do
      allow(SwayLogging).to receive(:warn)

      expect(described_class.cache_control_for(classifier_sized_prefix, model: "claude-haiku-5-5")).to be_nil
    end

    it "does not log when the marker is attached" do
      prefix = summary_sized_prefix
      expect(SwayLogging).not_to receive(:warn)

      described_class.cache_control_for(prefix, model: "claude-sonnet-5-5")
    end
  end

  # The point of the whole exercise: the two shipped prompts have to
  # report honestly against the model operators get by default, so nobody
  # builds another assumption on a marker that never fires.
  describe "the shipped prompts against the operator default model" do
    let(:prompt_cache_default_model) { AdminSetting::SUPPORTED_MODELS.first }

    it "confirms the default is still Haiku 5.5 — the whole gate turns on this" do
      expect(prompt_cache_default_model).to start_with("claude-haiku-5-5")
    end
  end
end
