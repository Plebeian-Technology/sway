# frozen_string_literal: true

require "rails_helper"
require "tmpdir"

RSpec.describe Eval::ReferenceSetSelector do
  let(:sway_locale) { create(:sway_locale, :baltimore) }
  let(:district) { create(:district, sway_locale: sway_locale) }
  let(:legislator) { create(:legislator, district: district) }

  around do |example|
    Dir.mktmpdir do |tmp|
      with_app_config(:legislation, legislation_diffs_root: tmp) { example.run }
    end
  end

  # Every bill this spec builds carries diff_content (a "summary source"),
  # matching what the selector's corpus query requires, and by default a
  # diff-markdown FILE on disk -- the thing the selector actually gates on.
  # testimony_chars: 0 puts a bill in the no-testimony pool.
  def banded_bill(testimony_chars:, diff_markdown_chars: 500, diff_file: true)
    @bill_sequence = (@bill_sequence || 0) + 1
    bill = create(
      :bill,
      sway_locale: sway_locale,
      legislator: legislator,
      scheduled_release_date_utc: @bill_sequence.days.ago
    )
    create(
      :bill_llm_provisioning,
      bill: bill,
      diff_content: "present",
      extracted_testimony: testimony_chars.positive? ? ("T" * testimony_chars) : ""
    )
    if diff_file
      path = Legislation::Paths.diff_markdown_file(bill.external_id, sway_locale: sway_locale.name)
      path.dirname.mkpath
      path.write("D" * diff_markdown_chars)
    end
    bill
  end

  def banded_bills(count, testimony_chars:, diff_markdown_chars: 500, diff_file: true, &block)
    Array.new(count) do |i|
      chars = block ? block.call(i) : testimony_chars
      banded_bill(testimony_chars: chars, diff_markdown_chars: diff_markdown_chars, diff_file: diff_file)
    end
  end

  # A minimal corpus that fills all 30 slots without collision: one
  # truncation-band bill, two control-band bills, 21 bulk_10k_50k bills
  # (the whole remainder), and six no-testimony bills.
  def build_valid_corpus
    cap = described_class.truncation_cap
    banded_bill(testimony_chars: cap + 1_000)
    banded_bill(testimony_chars: cap - 1_000)
    banded_bill(testimony_chars: 90_000)
    banded_bills(21, testimony_chars: 0) { |i| 10_000 + i }
    banded_bills(6, testimony_chars: 0)
  end

  describe "the truncation and control boundary" do
    it "is read from BillPositionsPromptBuilder.max_testimony_chars at call time, not baked in at load time" do
      with_app_config(:llm, llm_max_testimony_chars: 5_000, llm_max_testimony_tokens: 100_000) do
        expect(described_class.truncation_cap).to eq(5_000)

        banded_bill(testimony_chars: 6_000)
        banded_bills(23, testimony_chars: 0) { |i| 2_000 + i }
        banded_bills(6, testimony_chars: 0)

        result = described_class.call

        expect(result.bands[:truncation]).to eq(1)
      end
    end
  end

  describe "#call" do
    it "returns a Result whose bands is the per-band count over the corpus and whose picks is the chosen list" do
      build_valid_corpus

      result = described_class.call

      expect(result).to be_a(described_class::Result)
      expect(result.bands).to eq(
        truncation: 1, control: 2, bulk_10k_50k: 21, bulk_1k_10k: 0, bulk_under_1k: 0
      )
      expect(result.picks.length).to eq(24)
      expect(result.no_testimony_picks.length).to eq(6)
    end
  end

  describe "whole-band selection and bulk fill" do
    it "takes the truncation and control bands whole and fills the remainder from the bulk bands" do
      build_valid_corpus

      result = described_class.call

      expect(result.picks.count { |p| p[:band] == :truncation }).to eq(1)
      expect(result.picks.count { |p| p[:band] == :control }).to eq(2)
      expect(result.picks.count { |p| p[:band] == :bulk_10k_50k }).to eq(21)
    end

    it "fills the bulk remainder from the largest testimony-length band first, not the largest population" do
      # bulk_10k_50k holds only 2 bills; bulk_1k_10k holds 23 -- population
      # says take from 1k_10k first, but the band's testimony-length RANGE
      # says take from 10k_50k first. No truncation/control bills at all,
      # so the full 24-slot remainder is filled entirely from the bulk bands.
      banded_bills(2, testimony_chars: 0) { |i| 15_000 + i }
      banded_bills(23, testimony_chars: 0) { |i| 2_000 + i }
      banded_bills(6, testimony_chars: 0)

      result = described_class.call

      expect(result.picks.count { |p| p[:band] == :bulk_10k_50k }).to eq(2)
      expect(result.picks.count { |p| p[:band] == :bulk_1k_10k }).to eq(22)
    end
  end

  describe "the band collision" do
    it "raises BandCollisionError naming the tally instead of sampling when the whole bands alone fill or exceed 24 slots" do
      cap = described_class.truncation_cap
      banded_bills(25, testimony_chars: 0) { |i| cap + 1 + i }
      banded_bills(6, testimony_chars: 0)

      expect { described_class.call }.to raise_error(described_class::BandCollisionError, /25/)
    end
  end

  describe "the six no-testimony picks" do
    it "raises naming how many were found when fewer than six bills carry a summary source but no testimony" do
      build_valid_corpus
      # Only five no-testimony bills exist in build_valid_corpus's six -- delete one.
      BillLlmProvisioning.where(extracted_testimony: "").first!.destroy!

      expect { described_class.call }.to raise_error(described_class::InsufficientNoTestimonyError, /found 5/)
    end
  end

  describe "manual substitutions" do
    it "replaces a pick drawn from the 10k-50k band, without growing the set" do
      # 26 candidates in the 10k-50k band: the natural fill selects the
      # strongest 24, leaving two spares. A substitution's replacement
      # target is realistically one of those spares -- a fresh bill with
      # enough testimony to rank inside the top 24 would just get picked
      # naturally and never need a substitution at all.
      bills = banded_bills(26, testimony_chars: 0) { |i| 10_000 + i }
      banded_bills(6, testimony_chars: 0)

      natural = described_class.call
      picked_id = natural.picks.first.fetch(:external_id)
      spare_id = bills.map(&:external_id).find { |id| natural.picks.none? { |p| p[:external_id] == id } }

      result = described_class.call(manual_substitutions: [{from: picked_id, to: spare_id}])

      expect(result.picks.length).to eq(24)
      expect(result.picks.pluck(:external_id)).to include(spare_id)
      expect(result.picks.pluck(:external_id)).not_to include(picked_id)
      replaced = result.picks.find { |p| p[:external_id] == spare_id }
      expect(replaced[:substituted_for]).to eq(picked_id)
      expect(result.substitutions_applied).to eq([{from: picked_id, to: spare_id}])
    end

    it "raises when the named id is not currently a pick in the 10k-50k band" do
      build_valid_corpus

      expect {
        described_class.call(manual_substitutions: [{from: "not-a-real-pick", to: "also-fake"}])
      }.to raise_error(described_class::InvalidSubstitutionError, /not-a-real-pick/)
    end
  end

  describe "missing diff markdown" do
    it "collects a chosen bill with no diff markdown file into excluded_for_missing_diff and raises naming it" do
      cap = described_class.truncation_cap
      missing = banded_bill(testimony_chars: cap + 1_000, diff_file: false)
      banded_bill(testimony_chars: cap - 1_000)
      banded_bill(testimony_chars: 90_000)
      banded_bills(21, testimony_chars: 0) { |i| 10_000 + i }
      banded_bills(6, testimony_chars: 0)

      expect { described_class.call }.to raise_error(described_class::MissingDiffMarkdownError, /#{missing.external_id}/)
    end
  end

  describe "deterministic ordering" do
    it "produces identical picks across two calls over an unchanged corpus" do
      build_valid_corpus

      first = described_class.call
      second = described_class.call

      expect(second.picks).to eq(first.picks)
      expect(second.no_testimony_picks).to eq(first.no_testimony_picks)
    end
  end

  describe "SOURCE_CHAR_BANDS" do
    it "is reported over the chosen 30 and never used to select -- picks are unchanged when only source lengths change" do
      build_valid_corpus

      before_picks = described_class.call.picks.pluck(:external_id)

      # Rewrite every chosen bill's diff markdown to a wildly different
      # length -- large enough to land in the over-cap band.
      cap = described_class.source_cap
      Bill.find_each do |bill|
        path = Legislation::Paths.diff_markdown_file(bill.external_id, sway_locale: bill.sway_locale.name)
        path.write("D" * (cap + 1_000)) if path.exist?
      end

      result = described_class.call

      expect(result.picks.pluck(:external_id)).to eq(before_picks)
      expect(result.source_char_bands[:over_source_cap]).to eq(described_class::SET_SIZE)
    end

    it "reads its top band's lower boundary from BillSummaryPromptBuilder.max_source_chars at call time" do
      with_app_config(:llm, llm_max_source_chars: 100) do
        expect(described_class.source_cap).to eq(100)

        # build_valid_corpus's bills each carry 500 diff-markdown chars --
        # under the default (production) source cap but over this 100-char
        # override, so an over_source_cap tally here proves the boundary
        # actually moved rather than merely being present in the source.
        build_valid_corpus

        result = described_class.call

        expect(result.source_char_bands[:over_source_cap]).to eq(described_class::SET_SIZE)
        expect(result.source_char_bands[:under_source_cap]).to eq(0)
      end
    end
  end
end
